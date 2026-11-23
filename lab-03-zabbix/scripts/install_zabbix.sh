#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Запусти сценарий от root: sudo bash install_zabbix.sh"
[[ -r /etc/os-release ]] || die "Не найден /etc/os-release"
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Поддерживается Ubuntu; обнаружено: ${PRETTY_NAME:-unknown}"

case "${VERSION_ID:-}" in
  22.04) UBUNTU_CODENAME="jammy" ;;
  24.04) UBUNTU_CODENAME="noble" ;;
  26.04) UBUNTU_CODENAME="resolute" ;;
  *) die "Поддерживаются Ubuntu 22.04, 24.04 и 26.04; обнаружено: ${PRETTY_NAME:-unknown}" ;;
esac

if [[ -n "${VERSION_CODENAME:-}" && "$VERSION_CODENAME" != "$UBUNTU_CODENAME" ]]; then
  die "Кодовое имя ОС не совпадает с VERSION_ID: ${VERSION_CODENAME} != $UBUNTU_CODENAME"
fi

command -v systemctl >/dev/null || die "Не обнаружен systemd"
command -v openssl >/dev/null || die "Установи openssl перед запуском"
command -v dpkg >/dev/null || die "Не обнаружен dpkg"

export DEBIAN_FRONTEND=noninteractive

# Remove a repository package configured for another Ubuntu release.
# This is important when upgrading this lab script after an earlier failed run.
if dpkg-query -W -f='${db:Status-Status}' zabbix-release 2>/dev/null | grep -qx "installed"; then
  log "Удаление ранее установленного пакета zabbix-release для переустановки под $UBUNTU_CODENAME"
  dpkg --remove zabbix-release
fi
for old_source in /etc/apt/sources.list.d/zabbix.list /etc/apt/sources.list.d/zabbix.sources; do
  if [[ -f "$old_source" ]]; then
    cp -a "$old_source" "${old_source}.pre-lab.$(date +%Y%m%d%H%M%S)"
    rm -f "$old_source"
  fi
done

log "Обновление индексов APT для Ubuntu $VERSION_ID ($UBUNTU_CODENAME)"
apt-get update

repo_deb="$(mktemp --suffix=.deb)"
mysql_defaults=""
cleanup() {
  rm -f "$repo_deb"
  [[ -z "$mysql_defaults" ]] || rm -f "$mysql_defaults"
}
trap cleanup EXIT

repo_url="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu${VERSION_ID}_all.deb"
log "Загрузка официального репозитория Zabbix 7.4 для Ubuntu $VERSION_ID"
wget -q -O "$repo_deb" "$repo_url" || die "Не удалось скачать пакет репозитория Zabbix: $repo_url"
dpkg -i "$repo_deb"
apt-get update

log "Установка MySQL, Zabbix, Nginx и PHP-модулей из репозиториев текущей Ubuntu"
apt-get install -y mysql-server zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent nginx locales php-fpm php-mysql php-gd php-xml php-bcmath php-mbstring php-curl php-ldap
locale-gen en_US.UTF-8

PHP_VERSION="$(php -r 'printf("%d.%d", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);')"
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
PHP_FPM_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
[[ -d "/etc/php/${PHP_VERSION}/fpm" ]] || die "Не найден каталог PHP-FPM для PHP $PHP_VERSION"
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
  mysql_defaults="$(mktemp)"
  chmod 600 "$mysql_defaults"
  cat > "$mysql_defaults" <<SQL
[client]
user=zabbix
password=$DB_PASS
default-character-set=utf8mb4
SQL
  zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --defaults-extra-file="$mysql_defaults" zabbix
  rm -f "$mysql_defaults"
  mysql_defaults=""
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
chown root:zabbix "$server_conf"
chmod 640 "$server_conf"

log "Настройка Nginx: порт 8080 и server_name localhost"
nginx_conf="/etc/zabbix/nginx.conf"
[[ -f "$nginx_conf" ]] || die "Не найден $nginx_conf (проверь пакет zabbix-nginx-conf)"
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
    raise SystemExit("В nginx.conf не найдена директива listen; настрой порт 8080 вручную")
if not server_seen:
    raise SystemExit("В nginx.conf не найдена директива server_name; настрой localhost вручную")
path.write_text("\n".join(result) + "\n")
PY

# The Zabbix package normally creates this include. On package variants that
# do not, add a symlink so the distribution's nginx.conf loads the Zabbix vhost.
nginx_link="/etc/nginx/conf.d/zabbix.conf"
if [[ ! -e "$nginx_link" && ! -L "$nginx_link" ]]; then
  ln -s "$nginx_conf" "$nginx_link"
fi

log "Настройка часового пояса PHP $PHP_VERSION"
cp -an "$PHP_FPM_INI" "${PHP_FPM_INI}.pre-lab" || true
if grep -qE '^[;[:space:]]*date\.timezone[[:space:]]*=' "$PHP_FPM_INI"; then
  sed -ri 's|^[;[:space:]]*date\.timezone[[:space:]]*=.*|date.timezone = Europe/Moscow|' "$PHP_FPM_INI"
else
  printf '\ndate.timezone = Europe/Moscow\n' >> "$PHP_FPM_INI"
fi

log "Настройка локального агента"
agent_conf="/etc/zabbix/zabbix_agentd.conf"
[[ -f "$agent_conf" ]] || die "Не найден $agent_conf"
cp -an "$agent_conf" "${agent_conf}.pre-lab" || true
python3 - "$agent_conf" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
values = {"Server": "127.0.0.1", "ServerActive": "127.0.0.1", "Hostname": "Zabbix-local"}
lines = path.read_text().splitlines()
result = []
seen = set()
for line in lines:
    matched = next((key for key in values if re.match(r"^\s*#?\s*" + re.escape(key) + r"\s*=", line)), None)
    if matched:
        if matched not in seen:
            result.append(matched + "=" + values[matched])
            seen.add(matched)
    else:
        result.append(line)
for key, value in values.items():
    if key not in seen:
        result.append(key + "=" + value)
path.write_text("\n".join(result) + "\n")
PY

log "Проверка конфигурации Nginx"
nginx -t
log "Включение и перезапуск сервисов"
systemctl enable mysql nginx "$PHP_FPM_SERVICE" zabbix-server zabbix-agent
systemctl restart mysql "$PHP_FPM_SERVICE" zabbix-server zabbix-agent nginx

log "Установка завершена"
printf 'Ubuntu: %s (%s)\n' "$VERSION_ID" "$UBUNTU_CODENAME"
printf 'PHP-FPM: %s\n' "$PHP_FPM_SERVICE"
printf 'Frontend: http://localhost:8080\n'
printf 'DB password file (root only): %s\n' "$DB_PASS_FILE"
printf 'Agent hostname: Zabbix-local\n'
printf 'Следующий шаг: настрой Frontend в браузере, затем запусти scripts/configure_host.py\n'
