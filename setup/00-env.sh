#!/usr/bin/env bash
set -euo pipefail

# =========
# Network
# =========
export NET_CIDR="192.168.8.0/21"
export GATEWAY="192.168.8.1"
export DNS1="8.8.8.8"
export DNS2="1.1.1.1"

# =========
# Nodes (edit here if your IP differs)
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
# Kubernetes (for master/worker)
# =========
# Choose your Kubernetes minor version repo. You can change later if you want.
export K8S_MINOR="1.30"

# Pod network (Flannel default)
export POD_CIDR="10.244.0.0/16"
export SVC_CIDR="10.96.0.0/12"

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
