#!/usr/bin/env bash
set -Eeuo pipefail

services=(mysql zabbix-server zabbix-agent php8.1-fpm nginx)
failed=0
for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    printf 'OK      %s is active\n' "$service"
  else
    printf 'FAILED  %s is not active\n' "$service"
    systemctl --no-pager --full status "$service" || true
    failed=1
  fi
done

printf '\nListening sockets:\n'
ss -lntp | grep -E ':(8080|10050|10051)([[:space:]]|$)' || true

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
printf '\nВсе проверенные службы активны.\n'
