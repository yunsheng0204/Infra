#!/bin/bash
set -e

ROLE="$1"

if [[ -z "$ROLE" ]]; then
  echo "Usage: $0 {proxmox|master|worker|db}"
  exit 1
fi

GATEWAY="192.168.0.1"
DNS="8.8.8.8"

# =========================
# detect interface
# =========================
detect_iface() {
  nmcli -t -f DEVICE,TYPE device status | grep ethernet | cut -d: -f1 | head -n1
}

# =========================
# Proxmox Host
# =========================
setup_proxmox() {
  IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth|^en' | head -n1)

  if [[ -z "$IFACE" ]]; then
    echo "No physical interface found"
    exit 1
  fi

  echo "[Proxmox] Using interface: $IFACE"

  cat <<EOF >/etc/network/interfaces
auto lo
iface lo inet loopback

iface $IFACE inet manual

auto br0
iface br0 inet static
    address 192.168.0.10/24
    gateway $GATEWAY
    bridge_ports $IFACE
    bridge_stp off
    bridge_fd 0
EOF

  echo "[Proxmox] Reloading network"
  ifreload -a
}

# =========================
# VM (Rocky Linux)
# =========================
setup_vm() {
  ROLE="$1"

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
      echo "Invalid VM role"
      exit 1
      ;;
  esac

  IFACE=$(detect_iface)

  if [[ -z "$IFACE" ]]; then
    echo "No ethernet interface found"
    exit 1
  fi

  echo "[VM] Interface: $IFACE"
  echo "[VM] Hostname : $HOSTNAME"
  echo "[VM] IP       : $IP_ADDR"

  hostnamectl set-hostname "$HOSTNAME"

  nmcli con delete "$IFACE" || true

  nmcli con add type ethernet \
    con-name "$IFACE" \
    ifname "$IFACE" \
    ipv4.method manual \
    ipv4.addresses "$IP_ADDR" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS" \
    autoconnect yes

  nmcli con up "$IFACE"
}

# =========================
# main
# =========================
case "$ROLE" in
  proxmox)
    setup_proxmox
    ;;
  master|worker|db)
    setup_vm "$ROLE"
    ;;
  *)
    echo "Unknown role: $ROLE"
    exit 1
    ;;
esac

echo "================================="
echo " Setup completed for role: $ROLE"
echo "================================="
