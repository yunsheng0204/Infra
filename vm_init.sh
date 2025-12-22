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
DNS_SERVERS="192.168.0.1 8.8.8.8"

# =========================
# detect primary interface
# =========================
IFACE=$(ip route | awk '/default/ {print $5; exit}')

if [[ -z "$IFACE" ]]; then
  echo "[ERROR] Cannot detect network interface"
  exit 1
fi

echo "[INFO] Role      : $ROLE"
echo "[INFO] Hostname  : $HOSTNAME"
echo "[INFO] Interface : $IFACE"
echo "[INFO] IP        : $IP_ADDR"
echo "[INFO] Gateway   : $GATEWAY"
echo "[INFO] DNS       : $DNS_SERVERS"

# =========================
# hostname
# =========================
echo "[INFO] Setting hostname"
hostnamectl set-hostname "$HOSTNAME"

# =========================
# network (static IP, safe DNS)
# =========================
echo "[INFO] Configuring static IP (Proxmox-safe)"

nmcli con show "$IFACE" >/dev/null 2>&1 || {
  echo "[ERROR] NetworkManager connection not found for $IFACE"
  exit 1
}

nmcli con mod "$IFACE" \
  ipv4.method manual \
  ipv4.addresses "$IP_ADDR" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS_SERVERS" \
  ipv4.ignore-auto-dns yes

nmcli con up "$IFACE"

# =========================
# /etc/hosts (idempotent)
# =========================
echo "[INFO] Updating /etc/hosts"

grep -q "master-01" /etc/hosts || cat <<EOF >> /etc/hosts
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
# disable swap (k8s requirement)
# =========================
echo "[INFO] Disabling swap"
swapoff -a
sed -i '/swap/d' /etc/fstab

# =========================
# kernel & sysctl (k8s-ready)
# =========================
echo "[INFO] Kernel & sysctl configuration"

cat <<EOF > /etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

modprobe br_netfilter
sysctl --system

# =========================
# firewall (lab environment)
# =========================
echo "[INFO] Disabling firewalld (lab only)"
systemctl disable --now firewalld || true

# ===
