#!/usr/bin/env bash
set -euo pipefail

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

ok()   { echo -e "[${GREEN}PASS${NC}] $1"; }
fail() { echo -e "[${RED}FAIL${NC}] $1"; }
warn() { echo -e "[${YELLOW}WARN${NC}] $1"; }

echo "=== Kubernetes WORKER Node Check ==="

# A. Virtualization
if systemd-detect-virt | grep -qi kvm; then
  ok "Running on KVM"
else
  warn "Not detected as KVM"
fi

# B. OS basic
hostnamectl --static >/dev/null && ok "Hostname set"

systemctl is-active sshd &>/dev/null \
  && ok "SSHD active" || fail "SSHD not active"

timedatectl | grep -q "System clock synchronized: yes" \
  && ok "Time synchronized" || warn "Time not synchronized"

# C. Kernel modules
lsmod | grep -q br_netfilter \
  && ok "br_netfilter loaded" || fail "br_netfilter missing"

lsmod | grep -q overlay \
  && ok "overlay loaded" || fail "overlay missing"

# D. Container runtime
systemctl is-active containerd &>/dev/null \
  && ok "containerd active" || fail "containerd not active"

# E. Kubernetes components
rpm -q kubeadm kubelet &>/dev/null \
  && ok "kubeadm / kubelet installed" \
  || fail "Kubernetes packages missing"

systemctl is-enabled kubelet &>/dev/null \
  && ok "kubelet enabled" || warn "kubelet not enabled"

# F. Cluster join
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  ok "Node has joined cluster"
else
  warn "Node not joined yet (kubeadm join not run)"
fi

systemctl is-active kubelet &>/dev/null \
  && ok "kubelet active" \
  || warn "kubelet inactive (normal before join)"

echo "=== WORKER Check Finished ==="
