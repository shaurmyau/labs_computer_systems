#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Запусти сценарий от root: sudo bash install_zabbix.sh"
[[ -r /etc/os-release ]] || die "Не найден /etc/os-release"
. /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]] || die "Поддерживается Ubuntu 22.04; обнаружено: ${PRETTY_NAME:-unknown}"
command -v systemctl >/dev/null || die "Не обнаружен systemd"
command -v openssl >/dev/null || die "Установи openssl перед запуском"

export DEBIAN_FRONTEND=noninteractive
log "Обновление индексов APT"
apt-get update

repo_deb="$(mktemp --suffix=.deb)"
trap 'rm -f "$repo_deb"' EXIT
repo_url="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu22.04_all.deb"
log "Загрузка официального пакета репозитория Zabbix 7.4"
wget -q -O "$repo_deb" "$repo_url" || die "Не удалось скачать пакет репозитория Zabbix"
dpkg -i "$repo_deb"
apt-get update

log "Установка MySQL и компонентов Zabbix"
apt-get install -y mysql-server zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent nginx php8.1-fpm php8.1-mysql locales

systemctl enable --now mysql
DB_PASS_FILE="/root/.zabbix-db-password"
if [[ -s "$DB_PASS_FILE" ]]; then
  DB_PASS="$(cat "$DB_PASS_FILE")"
else
  DB_PASS="$(openssl rand -hex 24)"
  umask 077
  printf '%s\n' "$DB_PASS" > "$DB_PASS_FILE"
  chmod 600 "$DB_PASS_FILE"
fi
export DB_PASS

log "Создание базы данных и пользователя Zabbix"
mysql --protocol=socket -uroot <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
SQL

table_count="$(mysql --protocol=socket -uroot -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix'")"
if [[ "$table_count" -eq 0 ]]; then
  log "Импорт начальной схемы Zabbix"
  zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"$DB_PASS" zabbix
else
  log "В базе уже есть таблицы; повторный импорт пропущен"
fi
mysql --protocol=socket -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

log "Настройка пароля БД в zabbix_server.conf"
server_conf="/etc/zabbix/zabbix_server.conf"
[[ -f "$server_conf" ]] || die "Не найден $server_conf"
cp -an "$server_conf" "${server_conf}.pre-lab" || true
python3 - "$server_conf" "$DB_PASS" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
password = sys.argv[2]
lines = path.read_text().splitlines()
updated = False
result = []
for line in lines:
    if re.match(r"^\s*#?\s*DBPassword\s*=", line):
        if not updated:
            result.append("DBPassword=" + password)
            updated = True
    else:
        result.append(line)
if not updated:
    result.append("DBPassword=" + password)
path.write_text("\n".join(result) + "\n")
PY
chmod 640 "$server_conf"

log "Настройка Nginx: порт 8080 и server_name localhost"
nginx_conf="/etc/zabbix/nginx.conf"
[[ -f "$nginx_conf" ]] || die "Не найден $nginx_conf"
cp -an "$nginx_conf" "${nginx_conf}.pre-lab" || true
python3 - "$nginx_conf" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
listen_seen = server_seen = False
result = []
for line in lines:
    if re.match(r"^\s*#?\s*listen\s+[^;]+;", line):
        result.append("    listen 8080;")
        listen_seen = True
    elif re.match(r"^\s*#?\s*server_name\s+[^;]+;", line):
        result.append("    server_name localhost;")
        server_seen = True
    else:
        result.append(line)
if not listen_seen:
    raise SystemExit("В nginx.conf не найдена директива listen; настрой порт 8080 вручную по README")
if not server_seen:
    raise SystemExit("В nginx.conf не найдена директива server_name; настрой localhost вручную по README")
path.write_text("\n".join(result) + "\n")
PY
if [[ ! -e /etc/nginx/conf.d/zabbix.conf ]]; then
  ln -s /etc/zabbix/nginx.conf /etc/nginx/conf.d/zabbix.conf
fi

php_ini="/etc/php/8.1/fpm/php.ini"
if [[ -f "$php_ini" ]]; then
  cp -an "$php_ini" "${php_ini}.pre-lab" || true
  sed -ri 's|^[;[:space:]]*date.timezone[[:space:]]*=.*|date.timezone = Europe/Moscow|' "$php_ini"
fi

log "Настройка локального агента"
agent_conf="/etc/zabbix/zabbix_agentd.conf"
[[ -f "$agent_conf" ]] || die "Не найден $agent_conf"
cp -an "$agent_conf" "${agent_conf}.pre-lab" || true
sed -ri '/^[[:space:]#]*Hostname[[:space:]]*=/d' "$agent_conf"
printf '\nHostname=Zabbix-local\n' >> "$agent_conf"

log "Проверка конфигурации Nginx"
nginx -t
log "Включение и перезапуск сервисов"
systemctl enable mysql nginx php8.1-fpm zabbix-server zabbix-agent
systemctl restart mysql php8.1-fpm zabbix-server zabbix-agent nginx

log "Установка завершена"
printf 'Frontend: http://localhost:8080\n'
printf 'DB password file (root only): %s\n' "$DB_PASS_FILE"
printf 'Agent hostname: Zabbix-local\n'
printf 'Следующий шаг: настрой Frontend в браузере, затем запусти scripts/configure_host.py\n'
