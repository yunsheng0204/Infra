#!/usr/bin/env bash
set -euo pipefail
source ./00-env.sh

# This script is for MASTER VM only.
# IMPORTANT: To avoid breaking VM networking, it will NOT modify NIC/IP/GW/DNS/routes
# when DO_NOT_TOUCH_NETWORK=true (default).

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "Run as root"; }

verify_expected_ip() {
  # We don't touch networking. We only verify the expected IP exists,
  # because kubeadm will advertise MASTER_IP.
  if [[ "${DO_NOT_TOUCH_NETWORK}" == "true" ]]; then
    if ! ip -4 addr show | grep -qw "${MASTER_IP}"; then
      echo
      echo "[ERROR] MASTER_IP=${MASTER_IP} is NOT configured on this VM."
      echo "Fix the VM IP on Proxmox / inside the VM first, then rerun."
      echo
      ip -4 addr show || true
      echo
      die "Abort to avoid bringing up a broken cluster."
    fi
    log "Detected MASTER_IP=${MASTER_IP} on this VM (network unchanged)."
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
  dnf -y install curl wget vim git jq bash-completion chrony nfs-utils iproute-tc

  timedatectl set-timezone Asia/Taipei || true
  systemctl enable --now chronyd

  # SELinux permissive (lab-friendly)
  if command -v getenforce >/dev/null 2>&1; then
    setenforce 0 || true
    sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config || true
  fi

  # swap off (kubeadm requirement)
  swapoff -a || true
  sed -i.bak '/\sswap\s/d' /etc/fstab || true

  # kernel modules + sysctl for k8s
  if [[ "${K8S_KERNEL_TUNING}" == "true" ]]; then
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
  else
    warn "K8S_KERNEL_TUNING=false, skipping sysctl/modules tuning."
  fi
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

  dnf -y install kubelet kubeadm kubectl
  systemctl enable --now kubelet
}

firewall_master() {
  # Avoid changing firewall behavior unless it's already enabled.
  # We also DO NOT enable masquerade here to avoid unexpected NAT changes.
  if systemctl is-active --quiet firewalld; then
    log "firewalld is active, opening Kubernetes control-plane ports (no masquerade)."

    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=2379-2380/tcp
    firewall-cmd --permanent --add-port=10250/tcp
    firewall-cmd --permanent --add-port=10257/tcp
    firewall-cmd --permanent --add-port=10259/tcp

    firewall-cmd --reload
  else
    warn "firewalld is not active; leaving firewall unchanged."
  fi
}

kubeadm_init() {
  kubeadm reset -f || true
  rm -rf /etc/cni/net.d || true

  kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --pod-network-cidr="${POD_CIDR}" \
    --service-cidr="${SVC_CIDR}"

  mkdir -p /root/.kube
  cp -f /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config

  kubeadm token create --print-join-command > /root/kubeadm_join.sh
  chmod +x /root/kubeadm_join.sh

  echo
  echo "[OK] Master initialized."
  echo "Join command saved at: /root/kubeadm_join.sh"
  echo
  echo "Next step: install CNI (${CNI}). (This script does NOT apply CNI automatically.)"
}

main() {
  require_root
  hostnamectl set-hostname "${MASTER_HOST}"
  verify_expected_ip
  write_hosts
  base_os_tuning
  install_containerd
  install_kubernetes
  firewall_master
  kubeadm_init
}

main "$@"
