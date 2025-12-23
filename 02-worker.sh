#!/usr/bin/env bash
set -euo pipefail
source ./00-env.sh

# =========================
# Worker bootstrap (NO network changes)
# - Does NOT touch nmcli / static IP / routes / DNS
# - Does NOT configure bridges (br*/vmbr*) or NAT/masquerade
# =========================

require_root() { [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }

# Only verify the IP exists; we don't set it (network is managed by your teammate)
assert_ip_present() {
  local ip="$1"
  if ! ip -4 addr show | grep -qE "\b${ip}\b"; then
    echo "[ERROR] Expected IP ${ip} not found on this node."
    echo "        I will NOT change network settings."
    echo "        Please confirm this VM already has ${ip}/24 configured by your teammate."
    exit 1
  fi
}

write_hosts() {
  local marker_begin="# BEGIN CLUSTER HOSTS"
  local marker_end="# END CLUSTER HOSTS"
  sed -i "/${marker_begin}/,/${marker_end}/d" /etc/hosts || true
  cat >> /etc/hosts <<EOF
${marker_begin}
${MASTER_IP}  ${MASTER_HOST}
${WORKER_IP}  ${WORKER_HOST}
${DB_IP}      ${DB_HOST}
${GIT_IP}     ${GIT_HOST}
${LOG_IP}     ${LOG_HOST}
${marker_end}
EOF
}

base_os_tuning() {
  dnf -y update
  dnf -y install curl wget vim git jq bash-completion chrony iproute-tc nfs-utils

  timedatectl set-timezone Asia/Taipei || true
  systemctl enable --now chronyd

  if command -v getenforce >/dev/null 2>&1; then
    setenforce 0 || true
    sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config || true
  fi

  swapoff -a || true
  sed -i.bak '/\sswap\s/d' /etc/fstab || true

  # K8s prerequisite kernel modules (safe; does NOT create bridges)
  cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
  modprobe overlay || true
  modprobe br_netfilter || true

  # K8s prerequisite sysctl (no NAT rules here)
  cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system || true
}

install_containerd() {
  dnf -y install yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf -y install containerd.io

  mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
  systemctl enable --now containerd
}

install_kubernetes() {
  cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/rpm/repodata/repomd.xml.key
EOF

  # Worker needs kubelet + kubeadm; kubectl optional
  dnf -y install kubelet kubeadm
  systemctl enable --now kubelet
}

firewall_worker() {
  # Keep firewall changes minimal. No masquerade/NAT.
  systemctl enable --now firewalld || true

  # kubelet
  firewall-cmd --permanent --add-port=10250/tcp || true
  # NodePort range (if you plan to use NodePort services)
  firewall-cmd --permanent --add-port=30000-32767/tcp || true

  # If you later use Calico VXLAN, you may need 4789/udp; BGP mode may need 179/tcp.
  # (Leave to your security policy; uncomment only if required.)
  # firewall-cmd --permanent --add-port=4789/udp || true
  # firewall-cmd --permanent --add-port=179/tcp  || true

  firewall-cmd --reload || true
}

join_cluster() {
  # If already joined and not forcing, skip destructive reset.
  local force="${FORCE_REJOIN:-false}"

  if [[ -f /etc/kubernetes/kubelet.conf && "${force}" != "true" ]]; then
    echo "[INFO] /etc/kubernetes/kubelet.conf exists. This node looks already joined."
    echo "       Set FORCE_REJOIN=true if you really want to reset & re-join."
    return
  fi

  kubeadm reset -f || true

  if [[ -f /root/kubeadm_join.sh ]]; then
    bash /root/kubeadm_join.sh
    echo "[OK] Worker joined using /root/kubeadm_join.sh"
    return
  fi

  echo
  echo "⚠️  找不到 /root/kubeadm_join.sh"
  echo "請把 master 的 /root/kubeadm_join.sh 複製到這台再跑一次，或手動貼 kubeadm join 指令。"
  echo
}

main() {
  require_root
  hostnamectl set-hostname "${WORKER_HOST}"

  # Do NOT change network; only verify the intended IP is already present.
  assert_ip_present "${WORKER_IP}"

  write_hosts
  base_os_tuning
  install_containerd
  install_kubernetes
  firewall_worker
  join_cluster
}

main "$@"
