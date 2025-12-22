#!/bin/bash
set -e

ROLE="$1"

if [[ -z "$ROLE" ]]; then
  echo "Usage: $0 {master|worker|db}"
  exit 1
fi

# =========================
# role-based configuration
# =========================
case "$ROLE" in
  master)
    HOSTNAME="master-01"
    IP_ADDR="192.168.0.20/24"
    ;;
  worker)
    HOSTNAME="worker-01"
    IP_ADDR="192.168.0.30/24"
    ;;
  db)
    HOSTNAME="db-01"
    IP_ADDR="192.168.0.40/24"
    ;;
  *)
    echo "Invalid role: $ROLE"
    exit 1
    ;;
esac

GATEWAY="192.168.0.1"
DNS="8.8.8.8"

# =========================
# detect network interface
# =========================
IFACE=$(nmcli -t -f DEVICE,TYPE device status | grep ethernet | cut -d: -f1 | head -n1)

if [[ -z "$IFACE" ]]; then
  echo "[ERROR] No ethernet interface found"
  exit 1
fi

echo "[INFO] Role      : $ROLE"
echo "[INFO] Hostname  : $HOSTNAME"
echo "[INFO] Interface : $IFACE"
echo "[INFO] IP        : $IP_ADDR"

# =========================
# hostname
# =========================
echo "[INFO] Setting hostname"
hostnamectl set-hostname "$HOSTNAME"

# =========================
# network (static IP)
# =========================
echo "[INFO] Configuring static IP"
nmcli con mod "$IFACE" \
  ipv4.method manual \
  ipv4.addresses "$IP_ADDR" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS"

nmcli con up "$IFACE"

# =========================
# /etc/hosts
# =========================
echo "[INFO] Updating /etc/hosts"
cat <<EOF >> /etc/hosts
192.168.0.20 master-01
192.168.0.30 worker-01
192.168.0.40 db-01
EOF

# =========================
# base packages
# =========================
echo "[INFO] Installing base packages"
dnf -y install \
  vim \
  curl \
  wget \
  git \
  net-tools \
  bind-utils \
  bash-completion

# =========================
# disable swap (required by k8s)
# =========================
echo "[INFO] Disabling swap"
swapoff -a
sed -i '/swap/d' /etc/fstab

# =========================
# kernel & sysctl (k8s-ready)
# =========================
echo "[INFO] Kernel & sysctl settings"
cat <<EOF > /etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

modprobe br_netfilter
sysctl --system

# =========================
# firewall (lab mode)
# =========================
echo "[INFO] Disabling firewalld (lab environment)"
systemctl disable --now firewalld || true

# =========================
# role-specific notes
# =========================
echo "===================================="
echo "Initialization complete"
echo "Hostname : $HOSTNAME"
echo "IP       : $IP_ADDR"
echo "Gateway  : $GATEWAY"
echo
case "$ROLE" in
  master)
    echo "Next step:"
    echo "  - Install container runtime"
    echo "  - kubeadm init"
    ;;
  worker)
    echo "Next step:"
    echo "  - Install container runtime"
    echo "  - kubeadm join <master>"
    ;;
  db)
    echo "Next step:"
    echo "  - Install database (MySQL / PostgreSQL)"
    ;;
esac
echo "===================================="
