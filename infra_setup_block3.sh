#!/bin/bash

set -e

# install virtualization tools
sudo dnf -y update
sudo dnf -y groupinstall "Virtualization Host"
sudo systemctl enable --now libvirtd
sudo dnf -y install virt-top libguestfs-tools
lsmod | grep kvm

ethernet_name=$(ls /sys/class/net | grep -E '^(enp|ens|eth)')

# remove existing ethernet connection and set up a bridge network
sudo nmcli connection show
sudo nmcli connection delete "$ethernet_name"
sudo nmcli connection add type bridge con-name br0 ifname br0
sudo nmcli connection add type bridge-slave ifname "$ethernet_name" master br0

sudo nmcli connection modify br0 ipv4.addresses 192.168.0.12/24
sudo nmcli connection modify br0 ipv4.gateway 192.168.0.1
sudo nmcli connection modify br0 ipv4.dns 192.168.0.1
sudo nmcli connection modify br0 ipv4.method manual

# bring up bridge connection
sudo nmcli connection up br0

# basic verification
echo "=== Bridge status ==="
ip addr show br0
bridge link

echo "=== Routing table ==="
ip route

echo "=== Test gateway connectivity ==="
ping -c 3 192.168.0.1

# enable libvirt bridge networking
sudo systemctl restart libvirtd

# optional: allow bridge traffic through firewall
# sudo firewall-cmd --permanent --add-service=ssh
# sudo firewall-cmd --permanent --add-masquerade
# sudo firewall-cmd --reload

echo "========================================"
echo "KVM host with bridge br0 is ready"
echo "Host IP: 192.168.0.10"
echo
echo "Next steps:"
echo "1. Create VM and attach NIC to bridge br0"
echo "2. Assign VM IPs according to your design:"
echo "   - master node  : 192.168.0.22"
echo "   - worker node  : 192.168.0.32"
echo "   - db / gitlab  : 192.168.0.42"
echo "   - gslb         : 192.168.0.200"
echo "========================================"