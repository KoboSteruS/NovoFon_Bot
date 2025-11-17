# 🚀 Деплой NovoFon Bot на сервер

## 📋 Предварительные требования

- **Сервер:** Ubuntu 20.04+ / Debian 11+ (рекомендуется Ubuntu 22.04)
- **Python:** 3.11+ (проверьте: `python3 --version`)
- **Права:** sudo доступ
- **Порты:** 8000 (FastAPI), 8088 (Asterisk ARI), 5060 (SIP)

---

## 🔧 Шаг 1: Подготовка сервера

### 1.1 Обновление системы

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Установка базовых зависимостей

```bash
sudo apt install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    postgresql \
    postgresql-contrib \
    git \
    curl \
    build-essential
```

### 1.3 Создание пользователя для бота (опционально, но рекомендуется)

```bash
# Создать пользователя
sudo useradd -m -s /bin/bash novofon_bot

# Переключиться на пользователя
sudo su - novofon_bot
```

---

## 📦 Шаг 2: Установка проекта

### 2.1 Клонирование/загрузка проекта

```bash
# Если через git
cd ~
git clone <ваш_репозиторий> novofon_bot
cd novofon_bot

# Или если загрузили файлы через scp/sftp
# cd /path/to/novofon_bot
```

### 2.2 Создание виртуального окружения

```bash
python3.11 -m venv venv
source venv/bin/activate
```

### 2.3 Установка зависимостей

```bash
# Обновить pip
pip install --upgrade pip

# Установить зависимости
pip install -r requirements.txt

# Или минимальные (если не нужен Asterisk пока)
pip install -r requirements_minimal.txt
```

---

## 🗄️ Шаг 3: Настройка базы данных

### 3.1 Создание базы данных PostgreSQL

```bash
# Войти в PostgreSQL
sudo -u postgres psql

# В PostgreSQL консоли:
CREATE DATABASE novofon_bot;
CREATE USER novofon_user WITH PASSWORD 'ваш_надёжный_пароль';
GRANT ALL PRIVILEGES ON DATABASE novofon_bot TO novofon_user;
\q
```

### 3.2 Настройка PostgreSQL (опционально)

```bash
# Отредактировать конфиг для удалённого доступа (если нужно)
sudo nano /etc/postgresql/*/main/postgresql.conf
# Раскомментировать: listen_addresses = 'localhost'

sudo nano /etc/postgresql/*/main/pg_hba.conf
# Добавить: host novofon_bot novofon_user 127.0.0.1/32 md5

# Перезапустить PostgreSQL
sudo systemctl restart postgresql
```

---

## ⚙️ Шаг 4: Настройка конфигурации

### 4.1 Создание .env файла

```bash
# Скопировать шаблон
cp your_env_config.txt .env

# Отредактировать
nano .env
```

### 4.2 Настройка .env для продакшна

```env
# Application
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=8000
DEBUG=false

# Database
DATABASE_URL=postgresql+asyncpg://novofon_user:ваш_пароль@localhost:5432/novofon_bot

# NovoFon API
NOVOFON_API_KEY=ваш_ключ
NOVOFON_API_URL=https://api.novofon.ru
NOVOFON_FROM_NUMBER=+79991234567

# ElevenLabs
ELEVENLABS_API_KEY=ваш_ключ
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_MODEL=eleven_turbo_v2

# Asterisk ARI
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=ваш_ari_пароль
ASTERISK_ARI_APP_NAME=novofon_bot

# Redis (если используете)
REDIS_URL=redis://localhost:6379/0

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/novofon_bot/app.log
```

**⚠️ ВАЖНО:** Установите правильные права на .env:

```bash
chmod 600 .env
```

---

## 🗄️ Шаг 5: Инициализация базы данных

### 5.1 Создание таблиц

```bash
# Активировать venv
source venv/bin/activate

# Запустить init_db (создаст таблицы)
python -c "from app.database import init_db; import asyncio; asyncio.run(init_db())"

# Или через Alembic (если настроен)
alembic upgrade head
```

### 5.2 Проверка

```bash
# Подключиться к БД и проверить таблицы
sudo -u postgres psql novofon_bot
\dt
# Должны быть: calls, messages, call_queue
\q
```

---

## 🔧 Шаг 6: Настройка Asterisk (если нужен)

### 6.1 Установка Asterisk

```bash
# См. подробную инструкцию: docs/ASTERISK_SETUP.md
# Или краткую: ASTERISK_QUICKSTART.md

# Кратко:
sudo apt install -y asterisk
sudo systemctl start asterisk
sudo systemctl enable asterisk
```

### 6.2 Копирование конфигов

```bash
# Скопировать конфиги из проекта
sudo cp asterisk_configs/*.conf /etc/asterisk/

# Настроить pjsip.conf с вашими SIP данными
sudo nano /etc/asterisk/pjsip.conf

# Настроить ARI пароль
sudo nano /etc/asterisk/ari.conf

# Перезапустить Asterisk
sudo systemctl restart asterisk
```

---

## 🚀 Шаг 7: Создание systemd сервиса

### 7.1 Создание файла сервиса

```bash
sudo nano /etc/systemd/system/novofon-bot.service
```

### 7.2 Содержимое файла:

```ini
[Unit]
Description=NovoFon Voice Bot
After=network.target postgresql.service

[Service]
Type=simple
User=novofon_bot
Group=novofon_bot
WorkingDirectory=/home/novofon_bot/novofon_bot
Environment="PATH=/home/novofon_bot/novofon_bot/venv/bin"
ExecStart=/home/novofon_bot/novofon_bot/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always
RestartSec=10

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=novofon-bot

[Install]
WantedBy=multi-user.target
```

**⚠️ Замените пути на ваши!**

### 7.3 Активация сервиса

```bash
# Перезагрузить systemd
sudo systemctl daemon-reload

# Включить автозапуск
sudo systemctl enable novofon-bot

# Запустить
sudo systemctl start novofon-bot

# Проверить статус
sudo systemctl status novofon-bot

# Смотреть логи
sudo journalctl -u novofon-bot -f
```

---

## 🌐 Шаг 8: Настройка Nginx (опционально, но рекомендуется)

### 8.1 Установка Nginx

```bash
sudo apt install -y nginx
```

### 8.2 Создание конфига

```bash
sudo nano /etc/nginx/sites-available/novofon-bot
```

### 8.3 Содержимое:

```nginx
server {
    listen 80;
    server_name ваш_домен.com;  # Или IP адрес

    # Логи
    access_log /var/log/nginx/novofon-bot-access.log;
    error_log /var/log/nginx/novofon-bot-error.log;

    # Проксирование на FastAPI
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support (для ARI)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### 8.4 Активация

```bash
# Создать симлинк
sudo ln -s /etc/nginx/sites-available/novofon-bot /etc/nginx/sites-enabled/

# Проверить конфиг
sudo nginx -t

# Перезапустить Nginx
sudo systemctl restart nginx
```

---

## 🔒 Шаг 9: SSL сертификат (опционально, но рекомендуется)

### 9.1 Установка Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### 9.2 Получение сертификата

```bash
sudo certbot --nginx -d ваш_домен.com
```

Следуйте инструкциям. Certbot автоматически настроит Nginx.

---

## ✅ Шаг 10: Проверка работы

### 10.1 Проверка сервиса

```bash
# Статус
sudo systemctl status novofon-bot

# Логи
sudo journalctl -u novofon-bot -n 50

# Проверка порта
sudo netstat -tulpn | grep 8000
```

### 10.2 Проверка API

```bash
# Health check
curl http://localhost:8000/health

# Или через Nginx (если настроен)
curl http://ваш_домен.com/health
```

### 10.3 Проверка Swagger UI

Откройте в браузере:
- `http://ваш_сервер:8000/docs` (прямой доступ)
- `http://ваш_домен.com/docs` (через Nginx)

---

## 🔥 Шаг 11: Firewall (если используется)

### 11.1 UFW (Ubuntu)

```bash
# Разрешить HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Разрешить SSH (ВАЖНО!)
sudo ufw allow 22/tcp

# Разрешить SIP (если нужен)
sudo ufw allow 5060/udp
sudo ufw allow 10000:20000/udp  # RTP диапазон

# Включить firewall
sudo ufw enable

# Проверить статус
sudo ufw status
```

---

## 📊 Шаг 12: Мониторинг

### 12.1 Просмотр логов

```bash
# Логи приложения
tail -f /var/log/novofon_bot/app.log

# Логи systemd
sudo journalctl -u novofon-bot -f

# Логи Nginx
sudo tail -f /var/log/nginx/novofon-bot-access.log
```

### 12.2 Проверка ресурсов

```bash
# CPU и память
htop

# Дисковое пространство
df -h

# Процессы Python
ps aux | grep python
```

---

## 🆘 Troubleshooting

### Проблема: Сервис не запускается

```bash
# Проверить логи
sudo journalctl -u novofon-bot -n 100

# Проверить .env файл
cat .env

# Проверить права на файлы
ls -la

# Проверить Python
which python
python --version
```

### Проблема: База данных не подключается

```bash
# Проверить PostgreSQL
sudo systemctl status postgresql

# Проверить подключение
psql -U novofon_user -d novofon_bot -h localhost

# Проверить DATABASE_URL в .env
```

### Проблема: Порт занят

```bash
# Найти процесс на порту 8000
sudo lsof -i :8000

# Убить процесс (если нужно)
sudo kill -9 <PID>
```

### Проблема: Asterisk не подключается

```bash
# Проверить Asterisk
sudo systemctl status asterisk

# Проверить ARI
curl -u novofon_bot:пароль http://localhost:8088/ari/asterisk/info

# Проверить конфиг
sudo asterisk -rx "core show version"
```

---

## 🔄 Обновление бота

### Когда нужно обновить код:

```bash
# Остановить сервис
sudo systemctl stop novofon-bot

# Обновить код (git pull или загрузить новые файлы)
cd ~/novofon_bot
git pull  # или загрузить файлы

# Обновить зависимости (если нужно)
source venv/bin/activate
pip install -r requirements.txt --upgrade

# Применить миграции БД (если есть)
alembic upgrade head

# Запустить снова
sudo systemctl start novofon-bot

# Проверить
sudo systemctl status novofon-bot
```

---

## 📋 Чек-лист деплоя

- [ ] Сервер обновлён (`apt update && apt upgrade`)
- [ ] Python 3.11+ установлен
- [ ] PostgreSQL установлен и настроен
- [ ] Проект загружен на сервер
- [ ] Виртуальное окружение создано
- [ ] Зависимости установлены
- [ ] `.env` файл создан и настроен
- [ ] База данных создана и таблицы инициализированы
- [ ] Asterisk установлен и настроен (если нужен)
- [ ] Systemd сервис создан и запущен
- [ ] Nginx настроен (опционально)
- [ ] SSL сертификат получен (опционально)
- [ ] Firewall настроен
- [ ] Health check проходит
- [ ] Swagger UI доступен
- [ ] Логи пишутся корректно

---

## 🎯 Быстрая команда для проверки

```bash
# Всё в одной команде
curl http://localhost:8000/health && \
sudo systemctl status novofon-bot | grep Active && \
psql -U novofon_user -d novofon_bot -c "SELECT COUNT(*) FROM calls;" && \
echo "✅ Всё работает!"
```

---

## 📚 Дополнительные ресурсы

- **Логи:** `/var/log/novofon_bot/app.log`
- **Systemd:** `sudo systemctl status novofon-bot`
- **Nginx:** `/var/log/nginx/novofon-bot-*.log`
- **PostgreSQL:** `sudo -u postgres psql novofon_bot`

---

**Готово! Бот должен работать на сервере!** 🎉

Если что-то не работает - проверьте логи и следуйте troubleshooting секции.

