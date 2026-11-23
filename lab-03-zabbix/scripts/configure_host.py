#!/usr/bin/env python3
"""Register the local Zabbix agent host and CPU > 80% / 5m trigger."""
from __future__ import annotations

import getpass
import json
import sys
import urllib.error
import urllib.request
from typing import Any

API_URL = "http://localhost:8080/api_jsonrpc.php"
HOST = "Zabbix-local"
GROUP = "Linux servers"
TEMPLATE = "Linux by Zabbix agent"
CPU_KEY = "system.cpu.util"
TRIGGER_NAME = "CPU load > 80% for 5m"


class ZabbixAPI:
    def __init__(self, url: str) -> None:
        self.url = url
        self.token: str | None = None
        self.request_id = 0

    def call(self, method: str, params: dict[str, Any]) -> Any:
        self.request_id += 1
        payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": self.request_id}
        headers = {"Content-Type": "application/json-rpc"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        req = urllib.request.Request(
            self.url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                body = json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Не удалось обратиться к API {self.url}: {exc}") from exc
        if "error" in body:
            err = body["error"]
            raise RuntimeError(f"Zabbix API {method}: {err.get('message')} — {err.get('data')}")
        return body.get("result")

    def login(self, username: str, password: str) -> None:
        self.token = self.call("user.login", {"username": username, "password": password})


def main() -> int:
    url = input(f"Zabbix API URL [{API_URL}]: ").strip() or API_URL
    username = input("Frontend username [Admin]: ").strip() or "Admin"
    password = getpass.getpass("Frontend password: ")
    if not password:
        print("Пароль не может быть пустым.", file=sys.stderr)
        return 2

    api = ZabbixAPI(url)
    try:
        api.login(username, password)
        groups = api.call("hostgroup.get", {"output": ["groupid", "name"], "filter": {"name": [GROUP]}})
        if groups:
            group_id = str(groups[0]["groupid"])
        else:
            group_id = str(api.call("hostgroup.create", {"name": GROUP})["groupids"][0])

        templates = api.call(
            "template.get",
            {"output": ["templateid", "host", "name"], "filter": {"host": [TEMPLATE]}},
        )
        if not templates:
            raise RuntimeError(f"Не найден шаблон {TEMPLATE}; проверь название в Configuration → Templates")
        template_id = str(templates[0]["templateid"])

        hosts = api.call("host.get", {"output": ["hostid", "host"], "filter": {"host": [HOST]}})
        if hosts:
            host_id = str(hosts[0]["hostid"])
            print(f"Узел {HOST} уже существует (hostid={host_id}); повторное создание пропущено.")
        else:
            created = api.call(
                "host.create",
                {
                    "host": HOST,
                    "name": "localhost (local agent)",
                    "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": "127.0.0.1", "dns": "", "port": "10050"}],
                    "groups": [{"groupid": group_id}],
                    "templates": [{"templateid": template_id}],
                },
            )
            host_id = str(created["hostids"][0])
            print(f"Создан узел {HOST} (hostid={host_id}).")

        items = api.call(
            "item.get",
            {"output": ["itemid", "name", "key_"], "hostids": [host_id], "search": {"key_": CPU_KEY}},
        )
        if not any(item.get("key_") == CPU_KEY for item in items):
            raise RuntimeError(
                f"На узле не найден item с ключом {CPU_KEY}. "
                "Проверь шаблон и ключ CPU item; при необходимости измени CPU_KEY в этом скрипте."
            )

        existing = api.call(
            "trigger.get",
            {"output": ["triggerid", "description"], "hostids": [host_id], "filter": {"description": [TRIGGER_NAME]}},
        )
        if existing:
            print(f"Триггер «{TRIGGER_NAME}» уже существует (triggerid={existing[0]['triggerid']}).")
        else:
            expression = f"avg(/{HOST}/{CPU_KEY},5m)>80"
            created = api.call(
                "trigger.create",
                {
                    "description": TRIGGER_NAME,
                    "expression": expression,
                    "priority": 2,
                    "status": 0,
                    "comments": "Учебный триггер: средняя загрузка CPU выше 80% за пять минут.",
                },
            )
            print(f"Создан триггер (triggerid={created['triggerids'][0]}): {expression}")

        print("Готово. Проверь Monitoring → Latest data через 1–2 интервала опроса.")
        return 0
    except (RuntimeError, KeyError, IndexError) as exc:
        print(f"Ошибка: {exc}", file=sys.stderr)
        return 1
    finally:
        if api.token:
            try:
                api.call("user.logout", {})
            except RuntimeError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
