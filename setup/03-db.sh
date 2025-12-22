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

setup_mariadb() {
  echo "[INFO] Installing MariaDB..."
  dnf -y update
  dnf -y install mariadb-server firewalld

  systemctl enable --now mariadb
  systemctl enable --now firewalld

  echo "[INFO] Configuring MariaDB bind address..."
  # 允許外部連線（K8s / VM）
  cat >/etc/my.cnf.d/99-custom.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
EOF

  systemctl restart mariadb

  echo "[INFO] Initializing MariaDB users and security..."

  # -----------------------------
  # 判斷 root 是否已有密碼
  # - 第一次安裝：root 無密碼
  # - 第二次之後：root 已有密碼
  # -----------------------------
  if mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1;" &>/dev/null; then
    PASS_ARG="-p${DB_ROOT_PASS}"
    echo "[INFO] MariaDB root password already set."
  else
    PASS_ARG=""
    echo "[INFO] MariaDB root password not set yet."
  fi

  # -----------------------------
  # 安全性初始化（等同 mysql_secure_installation）
  # 且具備 idempotent 特性（可重跑）
  # -----------------------------
  mysql -u root ${PASS_ARG} <<EOF
-- 設定 / 重設 root 密碼
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';

-- 移除匿名使用者
DELETE FROM mysql.user WHERE User='';

-- 移除 test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- 建立 / 確保應用程式帳號存在
CREATE USER IF NOT EXISTS '${DB_APP_USER}'@'${DB_APP_ALLOWED_CIDR}'
  IDENTIFIED BY '${DB_APP_PASS}';

-- 授權（Lab / Infra 環境建議先給完整權限）
GRANT ALL PRIVILEGES ON *.* TO '${DB_APP_USER}'@'${DB_APP_ALLOWED_CIDR}';

FLUSH PRIVILEGES;
EOF

  # -----------------------------
  # Firewalld：開放 MySQL 連線
  # -----------------------------
  firewall-cmd --permanent --add-service=mysql || true
  firewall-cmd --reload || true

  echo "[OK] MariaDB setup completed."
  echo "     - Listen on 0.0.0.0:3306"
  echo "     - root password set"
  echo "     - app user: ${DB_APP_USER}@${DB_APP_ALLOWED_CIDR}"
}


main() {
  require_root
  hostnamectl set-hostname "${DB_HOST}"

  local iface
  iface="$(detect_iface)"
  set_static_ip "$iface" "${DB_IP}"
  write_hosts

  setup_mariadb
if [[ "${ENABLE_NFS}" == "true" ]]; then
  echo "[INFO] NFS backup enabled"

  mkdir -p "${NFS_MOUNT}"

  # 先嘗試掛載（不中斷腳本）
  mount -t nfs "${NFS_SERVER}:${NFS_EXPORT}" "${NFS_MOUNT}" &>/dev/null || true

  # 避免重複寫入 /etc/fstab
  if ! grep -qs "${NFS_MOUNT}" /etc/fstab; then
    echo "${NFS_SERVER}:${NFS_EXPORT} ${NFS_MOUNT} nfs defaults,_netdev 0 0" >> /etc/fstab
    echo "[INFO] NFS entry added to /etc/fstab"
  else
    echo "[INFO] NFS entry already exists in /etc/fstab"
  fi

  # 每日備份
  cat >/etc/cron.daily/mariadb-backup <<EOF
#!/bin/bash
mysqldump -u root -p${DB_ROOT_PASS} --all-databases \
  > ${NFS_MOUNT}/mariadb-\$(date +\%F).sql
EOF
  chmod +x /etc/cron.daily/mariadb-backup
fi


}

main "$@"
