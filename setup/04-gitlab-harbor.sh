#!/usr/bin/env bash
set -euo pipefail
source ./00-env.sh

require_root() { [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }

detect_iface() {
  local iface
  iface="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="ethernet"{print $1; exit}')"
  [[ -n "${iface}" ]] || { echo "No ethernet iface found"; exit 1; }
  echo "$iface"
}

set_static_ip() {
  local iface="$1" ip="$2"
  local con
  con="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  if [[ -z "${con}" ]]; then
    con="$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  fi
  [[ -n "${con}" ]] || { echo "No nmcli connection found for $iface"; exit 1; }

  nmcli con mod "$con" ipv4.method manual ipv4.addresses "${ip}/24" ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS1} ${DNS2}" ipv4.ignore-auto-dns yes connection.autoconnect yes
  nmcli con up "$con"
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

install_docker() {
  dnf -y update
  dnf -y install yum-utils curl wget git firewalld

  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

  systemctl enable --now docker
  systemctl enable --now firewalld
}

deploy_gitlab() {
  mkdir -p /opt/gitlab
  cat >/opt/gitlab/docker-compose.yml <<EOF
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    hostname: "${GIT_HOST}"
    restart: always
    shm_size: "256m"
    ports:
      - "${GITLAB_HTTP_PORT}:80"
      - "${GITLAB_SSH_PORT}:22"
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GIT_IP}:${GITLAB_HTTP_PORT}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
        gitlab_rails['initial_root_password'] = '${GITLAB_ROOT_PASS}'
        puma['worker_processes'] = 2
        sidekiq['max_concurrency'] = 10
        postgresql['shared_buffers'] = "256MB"
        prometheus_monitoring['enable'] = false
    volumes:
      - /opt/gitlab/config:/etc/gitlab
      - /opt/gitlab/logs:/var/log/gitlab
      - /opt/gitlab/data:/var/opt/gitlab
EOF

  docker compose -f /opt/gitlab/docker-compose.yml up -d

  firewall-cmd --permanent --add-port=${GITLAB_HTTP_PORT}/tcp || true
  firewall-cmd --permanent --add-port=${GITLAB_SSH_PORT}/tcp || true
  firewall-cmd --reload || true

  echo "[OK] GitLab starting..."
  echo "URL: http://${GIT_IP}:${GITLAB_HTTP_PORT}"
  echo "SSH: ssh -p ${GITLAB_SSH_PORT} git@${GIT_IP}"
}

harbor_skeleton() {
  mkdir -p /opt/harbor
  cat >/opt/harbor/README.txt <<'EOF'
Harbor install note:

Harbor 通常需要：
- domain / FQDN（建議）或至少固定 IP
- TLS 憑證（Harbor 官方預設推薦 HTTPS）
- storage 設定（本機磁碟 / NFS / S3 相容）

我先幫你把目錄骨架建好：
/opt/harbor

如果你要我幫你「完整自動化 Harbor 安裝」
請回覆：
1) 你要用 IP 直接訪問？還是有 domain（例如 harbor.lab.local）？
2) 你要用哪個 storage？（本機 / NFS: 192.168.8.100 / S3）
EOF

  echo "[INFO] Harbor skeleton created at /opt/harbor"
}

main() {
  require_root
  hostnamectl set-hostname "${GIT_HOST}"

  local iface
  iface="$(detect_iface)"
  set_static_ip "$iface" "${GIT_IP}"
  write_hosts

  install_docker
  deploy_gitlab
  harbor_skeleton
}

main "$@"
