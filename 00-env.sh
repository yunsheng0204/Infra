#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Cluster inventory / IP plan
# NOTE:
# - Network/bridge/NAT is managed by Proxmox host already.
# - Scripts in this repo should NOT reconfigure NIC/IP/GW/DNS
#   on the VMs unless you explicitly turn it on.
# ==========================================================

# =========
# Nodes (5 VMs)
# =========
export MASTER_HOST="master"
export MASTER_IP="192.168.8.20"

export WORKER_HOST="worker"
export WORKER_IP="192.168.8.30"

export DB_HOST="db"
export DB_IP="192.168.8.40"

export GIT_HOST="git"
export GIT_IP="192.168.8.41"

export LOG_HOST="log"
export LOG_IP="192.168.8.42"

# =========
# Safety switches
# =========
# true  = do NOT touch NIC/IP/GW/DNS/route settings on the VM
# false = allow scripts to manage VM network (NOT recommended in your case)
export DO_NOT_TOUCH_NETWORK="${DO_NOT_TOUCH_NETWORK:-true}"

# Kernel/network sysctl tweaks required by Kubernetes (safe inside VM).
export K8S_KERNEL_TUNING="${K8S_KERNEL_TUNING:-true}"

# =========
# Kubernetes (master/worker)
# =========
# Choose Kubernetes minor version repo.
export K8S_MINOR="${K8S_MINOR:-1.30}"

# Pod/Service CIDR (MUST NOT overlap with 192.168.8.0/24)
export POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
export SVC_CIDR="${SVC_CIDR:-10.96.0.0/12}"

# CNI selection (install happens in a later stage; master init won't auto-apply)
export CNI="${CNI:-calico}"   # calico | flannel | none

# =========
# DB (MariaDB default)
# =========
export DB_ROOT_PASS="ChangeMeRoot!"
export DB_APP_USER="app"
export DB_APP_PASS="ChangeMeApp!"
export DB_APP_ALLOWED_CIDR="%"

# =========
# GitLab (docker compose)
# =========
export GITLAB_HTTP_PORT="8080"     # GitLab web on http://<GIT_IP>:8080
export GITLAB_SSH_PORT="2222"      # GitLab ssh on <GIT_IP>:2222
export GITLAB_ROOT_PASS="ChangeMeGitLabRoot!"

# =========
# Log server (rsyslog + optional Loki/Grafana)
# =========
export ENABLE_LOKI_STACK="true"    # true/false
export LOKI_HTTP_PORT="3100"
export GRAFANA_HTTP_PORT="3000"

# =========
# Optional: NAS mount (Synology)
# =========
export ENABLE_NFS="false"          # true/false
export NFS_SERVER="192.168.8.100"
export NFS_EXPORT="/volume1/share"
export NFS_MOUNT="/mnt/nas"
