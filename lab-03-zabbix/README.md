# Семинар 3. Установка и настройка Zabbix 7.4

## Цель

Развернуть Zabbix Server, Frontend и Agent на Ubuntu Server 22.04, использовать MySQL, проверить работу сервисов, зарегистрировать локальный узел и создать триггер на загрузку CPU выше 80% в течение пяти минут.

## Требования к среде

- Ubuntu Server 22.04 LTS, архитектура amd64.
- Пользователь root или запуск через sudo.
- Доступ в Интернет для загрузки пакетов Zabbix 7.4 и Ubuntu.
- Не менее 2 CPU, 4 ГБ RAM и 20 ГБ свободного места для учебной ВМ.
- Свободные TCP-порты 80/8080, 10050 и 10051.

## Установка

Из корня клонированного репозитория:

~~~bash
sudo bash lab-03-zabbix/scripts/install_zabbix.sh
~~~

Сценарий проверяет ОС, устанавливает репозиторий Zabbix 7.4 для Ubuntu 22.04, MySQL Server и компоненты Zabbix, создаёт базу и пользователя, импортирует схему только при пустой БД, сохраняет сгенерированный пароль в защищённом файле /root/.zabbix-db-password с правами 0600, настраивает Nginx на 8080, часовой пояс PHP и имя локального агента Zabbix-local.

Сценарий рассчитан на чистую учебную машину. Перед запуском на существующем сервере проверь конфликты с текущими MySQL/Nginx и сделай резервные копии конфигураций.

После установки открой http://localhost:8080. Учётные данные Frontend по умолчанию: Admin / zabbix. В мастере настройки выбери MySQL, хост localhost, базу zabbix, пользователя zabbix. Пароль возьми из файла:

~~~bash
sudo cat /root/.zabbix-db-password
~~~

Укажи имя сервера Zabbix, часовой пояс Europe/Moscow и заверши мастер. При первом входе измени пароль Admin.

## Добавление узла и триггера

После завершения мастера запусти:

~~~bash
sudo python3 lab-03-zabbix/scripts/configure_host.py
~~~

Сценарий запросит учётные данные Frontend, найдёт или создаст группу Linux servers, найдёт шаблон Linux by Zabbix agent, зарегистрирует узел Zabbix-local с интерфейсом агента 127.0.0.1:10050 и добавит триггер:

- Name: CPU load > 80% for 5m
- Severity: Warning
- Expression: avg(/Zabbix-local/system.cpu.util,5m)>80

Сценарий использует штатный JSON-RPC API Zabbix и стандартную библиотеку Python. Если в установленном шаблоне отличается ключ CPU item, скрипт завершится с понятной ошибкой; проверь ключ через Configuration → Hosts → Items и обнови выражение триггера согласно фактическому ключу.

## Проверка

~~~bash
sudo bash lab-03-zabbix/scripts/check_services.sh
sudo systemctl status zabbix-server zabbix-agent nginx mysql php8.1-fpm
sudo ss -lntp | grep -E ':8080|:10050|:10051'
~~~

В Frontend проверь Monitoring → Latest data, выбери Zabbix-local. После первого опроса должны появиться CPU, memory, filesystem и network items.

## Индивидуальное задание

Порядок регистрации метрик, фиксации значений и проверки триггера приведён в docs/individual-task.md. В документе есть пример заполнения таблицы; примерные числа необходимо заменить фактическими значениями со своего узла.

## Типовые проблемы

- Server не стартует: проверь DBPassword в /etc/zabbix/zabbix_server.conf и журнал journalctl -u zabbix-server -n 100.
- Frontend не открывается: проверь nginx -t, systemctl status nginx php8.1-fpm и порт 8080.
- Агент недоступен: проверь systemctl status zabbix-agent, Hostname=Zabbix-local, Server/ServerActive и доступность 127.0.0.1:10050.
- Нет CPU item: проверь привязку шаблона и перечень Items.
- Триггер не срабатывает: проверь Latest data, точный ключ CPU item, выражение и историю значений за последние пять минут.

Удаление не автоматизировано намеренно: оно может уничтожить существующие данные. Для чистой учебной ВМ удаляй компоненты и базу вручную после сохранения нужных материалов.
