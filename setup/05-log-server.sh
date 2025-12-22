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

  nmcli con mod "$con" ipv4.method manual ipv4.addresses "${ip}/21" ipv4.gateway "${GATEWAY}" \
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

install_rsyslog_server() {
  dnf -y update
  dnf -y install rsyslog firewalld

  mkdir -p /var/log/remote
  mkdir -p /var/log/remote
  chown -R rsyslog:rsyslog /var/log/remote
  chmod 755 /var/log/remote

  # enable UDP/TCP 514 receive
  cat >/etc/rsyslog.d/10-receiver.conf <<'EOF'
module(load="imudp")
input(type="imudp" port="514")

module(load="imtcp")
input(type="imtcp" port="514")

template(name="RemoteFmt" type="string" string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")
*.* ?RemoteFmt
& stop
EOF

  systemctl enable --now rsyslog
  systemctl enable --now firewalld

  firewall-cmd --permanent --add-port=514/udp || true
  firewall-cmd --permanent --add-port=514/tcp || true
  firewall-cmd --reload || true

  echo "[OK] rsyslog server listening on ${LOG_IP}:514 (udp/tcp)"

  cat >/etc/logrotate.d/remote <<'EOF'
/var/log/remote/*/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    delaycompress
    copytruncate
}
EOF
}

install_loki_stack_optional() {
  if [[ "${ENABLE_LOKI_STACK}" != "true" ]]; then
    echo "[INFO] ENABLE_LOKI_STACK=false, skip Loki/Grafana"
    return
  fi

  echo "[INFO] Installing Loki + Grafana stack..."

  # -----------------------------
  # Docker 安裝（idempotent）
  # -----------------------------
  dnf -y install yum-utils curl
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
  dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker

  # -----------------------------
  # Loki 目錄結構
  # -----------------------------
  mkdir -p /opt/loki/config
  mkdir -p /opt/loki/data

  # -----------------------------
  # Loki 最小可用設定檔（關鍵）
  # -----------------------------
  if [[ ! -f /opt/loki/config/local-config.yaml ]]; then
    cat >/opt/loki/config/local-config.yaml <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks
EOF
  fi

  # -----------------------------
  # docker-compose.yml（修正版）
  # -----------------------------
  cat >/opt/loki/docker-compose.yml <<EOF
services:
  loki:
    image: grafana/loki:2.9.8
    container_name: loki
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - /opt/loki/config:/etc/loki
      - /opt/loki/data:/loki
    ports:
      - "${LOKI_HTTP_PORT}:3100"
    restart: always

  grafana:
    image: grafana/grafana:10.4.2
    container_name: grafana
    ports:
      - "${GRAFANA_HTTP_PORT}:3000"
    restart: always
EOF

  # -----------------------------
  # 啟動 Loki / Grafana
  # -----------------------------
  docker compose -f /opt/loki/docker-compose.yml up -d

  # -----------------------------
  # 防火牆
  # -----------------------------
  firewall-cmd --permanent --add-port=${LOKI_HTTP_PORT}/tcp || true
  firewall-cmd --permanent --add-port=${GRAFANA_HTTP_PORT}/tcp || true
  firewall-cmd --reload || true

  echo "[OK] Loki running at:     http://${LOG_IP}:${LOKI_HTTP_PORT}"
  echo "[OK] Grafana running at: http://${LOG_IP}:${GRAFANA_HTTP_PORT}"
  echo "     Grafana default login: admin / admin"
}


main() {
  require_root
  hostnamectl set-hostname "${LOG_HOST}"

  local iface
  iface="$(detect_iface)"
  set_static_ip "$iface" "${LOG_IP}"
  write_hosts

  install_rsyslog_server
  install_loki_stack_optional
}

main "$@"
