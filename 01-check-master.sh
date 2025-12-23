#!/usr/bin/env bash
set -euo pipefail

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

ok()   { echo -e "[${GREEN}PASS${NC}] $1"; }
fail() { echo -e "[${RED}FAIL${NC}] $1"; }
warn() { echo -e "[${YELLOW}WARN${NC}] $1"; }

echo "=== Kubernetes MASTER Node Check ==="

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

sysctl net.bridge.bridge-nf-call-iptables | grep -q "= 1" \
  && ok "bridge-nf-call-iptables enabled" || fail "bridge-nf-call-iptables disabled"

# D. Container runtime
systemctl is-active containerd &>/dev/null \
  && ok "containerd active" || fail "containerd not active"

# E. Kubernetes components
rpm -q kubeadm kubelet kubectl &>/dev/null \
  && ok "kubeadm / kubelet / kubectl installed" \
  || fail "Kubernetes packages missing"

systemctl is-enabled kubelet &>/dev/null \
  && ok "kubelet enabled" || warn "kubelet not enabled"

# F. Cluster init
if [[ -f /etc/kubernetes/admin.conf ]]; then
  ok "kubeadm init completed"
else
  warn "kubeadm init not yet run"
fi

if command -v kubectl &>/dev/null && [[ -f /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl get nodes &>/dev/null \
    && ok "kubectl can access cluster" \
    || fail "kubectl cannot access cluster"
else
  warn "kubectl not usable yet"
fi

# G. CNI
if kubectl get pods -n kube-system 2>/dev/null | grep -qi calico; then
  ok "Calico detected"
else
  warn "CNI not detected (nodes may be NotReady)"
fi

echo "=== MASTER Check Finished ==="
