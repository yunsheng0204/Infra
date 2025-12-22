#!/usr/bin/env bash
set -euo pipefail
source ./00-env.sh

require_root() { [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }

detect_iface() {
  local iface
  iface="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="ethernet"{print $1; exit}')"
  [[ -n "${iface}" ]] || { echo "No ethernet iface found"; exit 1; }
  echo "$iface"
}

set_static_ip() {
  local iface="$1" ip="$2"
  local con
  con="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  if [[ -z "${con}" ]]; then
    con="$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  fi
  [[ -n "${con}" ]] || { echo "No nmcli connection found for $iface"; exit 1; }

  nmcli con mod "$con" ipv4.method manual ipv4.addresses "${ip}/21" ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS1} ${DNS2}" ipv4.ignore-auto-dns yes connection.autoconnect yes
  nmcli con up "$con"
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
  sed -i.bak '/\sswap\s/d' /etc/fstab

  cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
  modprobe overlay || true
  modprobe br_netfilter || true

  cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system
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

  dnf -y install kubelet kubeadm
  systemctl enable --now kubelet
}

firewall_worker() {
  systemctl enable --now firewalld || true

  # kubelet + NodePort range
  firewall-cmd --permanent --add-port=10250/tcp || true
  firewall-cmd --permanent --add-port=30000-32767/tcp || true

  # Flannel VXLAN
  firewall-cmd --permanent --add-port=8472/udp || true


  firewall-cmd --permanent --add-masquerade
  firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.244.0.0/16" accept'

  firewall-cmd --reload || true
}

join_cluster() {
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

  local iface
  iface="$(detect_iface)"
  set_static_ip "$iface" "${WORKER_IP}"
  write_hosts
  base_os_tuning
  install_containerd
  install_kubernetes
  firewall_worker
  join_cluster
}

main "$@"
