#!/bin/bash
set -e

echo "[INFO] Setting up INTERNAL KVM bridge (VM-safe, NAT only)"

# ===============================
# variables
# ===============================
BRIDGE=br0
BRIDGE_IP=192.168.0.10/24
BRIDGE_NET=192.168.0.0/24
EXT_IFACE=$(ip route show default | awk '{print $5}' | head -n1)

DISK_DIR=/var/lib/libvirt/images

# Rocky Linux 10.1 ISO
ROCKY_VERSION=10.1
ROCKY_ISO_NAME=Rocky-${ROCKY_VERSION}-x86_64-dvd1.iso
ISO_PATH=${DISK_DIR}/${ROCKY_ISO_NAME}
ROCKY_ISO_URL="https://download.rockylinux.org/pub/rocky/${ROCKY_VERSION}/isos/x86_64/${ROCKY_ISO_NAME}"

# ===============================
# install packages
# ===============================
echo "[INFO] Installing packages"
sudo dnf -y install \
  libvirt \
  virt-install \
  bridge-utils \
  dnsmasq \
  iptables-services \
  wget

sudo systemctl enable --now libvirtd

# ===============================
# create internal linux bridge (NO slave)
# ===============================
echo "[INFO] Configuring internal bridge ${BRIDGE}"

if ! nmcli connection show | grep -q "^${BRIDGE}"; then
  sudo nmcli connection add type bridge ifname ${BRIDGE} con-name ${BRIDGE}
fi

sudo nmcli connection modify ${BRIDGE} \
  ipv4.method manual \
  ipv4.addresses ${BRIDGE_IP} \
  ipv4.never-default yes \
  ipv6.method ignore

sudo nmcli connection up ${BRIDGE}

# ===============================
# enable IP forward
# ===============================
echo "[INFO] Enabling IP forwarding"
sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# ===============================
# NAT (br0 -> external iface)
# ===============================
echo "[INFO] Setting up NAT: ${BRIDGE_NET} -> ${EXT_IFACE}"

sudo iptables -t nat -C POSTROUTING -s ${BRIDGE_NET} -o ${EXT_IFACE} -j MASQUERADE 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -s ${BRIDGE_NET} -o ${EXT_IFACE} -j MASQUERADE

sudo iptables -C FORWARD -i ${BRIDGE} -o ${EXT_IFACE} -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i ${BRIDGE} -o ${EXT_IFACE} -j ACCEPT

sudo iptables -C FORWARD -i ${EXT_IFACE} -o ${BRIDGE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i ${EXT_IFACE} -o ${BRIDGE} -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo service iptables save || true

# ===============================
# download Rocky Linux 10.1 ISO
# ===============================
echo "[INFO] Checking Rocky Linux 10.1 ISO"

sudo mkdir -p ${DISK_DIR}

if [ ! -f "${ISO_PATH}" ]; then
  echo "[INFO] ISO not found, downloading Rocky Linux ${ROCKY_VERSION}"
  sudo wget -O "${ISO_PATH}" "${ROCKY_ISO_URL}"
else
  echo "[INFO] ISO already exists: ${ISO_PATH}"
fi

# ===============================
# result (host)
# ===============================
echo "======================================"
echo "Internal KVM bridge ready"
echo
echo "Host:"
echo "  - External NIC : ${EXT_IFACE} (DHCP, Internet)"
echo "  - Internal br0 : 192.168.0.10/24"
echo
echo "Guests will access Internet via NAT"
echo "======================================"

# ===============================
# create guest VMs
# ===============================
echo "[INFO] Creating guest VMs (master / worker / db)"

create_vm () {
  NAME=$1

  if virsh list --all | grep -q " ${NAME} "; then
    echo "[SKIP] VM ${NAME} already exists"
    return
  fi

  echo "[INFO] Creating VM: ${NAME}"

  sudo virt-install \
    --name ${NAME} \
    --ram 2048 \
    --vcpus 2 \
    --disk path=${DISK_DIR}/${NAME}.qcow2,size=20 \
    --os-variant rocky10 \
    --network bridge=${BRIDGE},model=virtio \
    --graphics none \
    --console pty,target_type=serial \
    --cdrom ${ISO_PATH}
}

create_vm master-01
create_vm worker-01
create_vm db-01

echo "======================================"
echo "VM creation started"
echo
echo "Next steps:"
echo "  - Install OS inside each VM"
echo "  - Set static IPs:"
echo "      master : 192.168.0.20"
echo "      worker : 192.168.0.30"
echo "      db     : 192.168.0.40"
echo "  - Gateway  : 192.168.0.10"
echo "======================================"
