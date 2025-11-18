# 🚀 Полная установка NovoFon Bot с нуля

## 📊 Требования к серверу

### Минимальные требования:
- **ОС:** Ubuntu 20.04+ / Debian 11+ (рекомендуется Ubuntu 22.04)
- **RAM:** 2 GB (минимум), 4 GB (рекомендуется)
- **Диск:** 5-10 GB свободного места
- **CPU:** 2 ядра (минимум)
- **Сеть:** Публичный IP адрес
- **Права:** sudo/root доступ

### Порты:
- **80/tcp** - HTTP (Nginx)
- **443/tcp** - HTTPS (опционально)
- **9000/tcp** - FastAPI (внутренний, через Nginx)
- **8088/tcp** - Asterisk ARI (внутренний)
- **5060/udp** - SIP
- **10000-20000/udp** - RTP (аудио)

---

## ⚡ Быстрая установка (автоматическая)

### Вариант 1: Автоматический скрипт

```bash
# 1. Загрузите проект на сервер
git clone <ваш_репозиторий> /opt/novofon_bot
# Или загрузите файлы через scp/sftp

# 2. Перейдите в директорию
cd /opt/novofon_bot

# 3. Сделайте скрипт исполняемым
chmod +x install.sh

# 4. Запустите установку
sudo bash install.sh
```

Скрипт спросит все необходимые данные и установит всё автоматически!

---

## 📝 Ручная установка (пошагово)

### Шаг 1: Подготовка сервера

```bash
# Обновить систему
sudo apt update && sudo apt upgrade -y

# Установить базовые зависимости
sudo apt install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    postgresql \
    postgresql-contrib \
    git \
    curl \
    wget \
    build-essential \
    nginx \
    ufw
```

---

### Шаг 2: Создание пользователя

```bash
# Создать пользователя
sudo useradd -m -s /bin/bash novofon_bot

# Переключиться на пользователя
sudo su - novofon_bot
```

---

### Шаг 3: Установка проекта

```bash
# Создать директорию
sudo mkdir -p /opt/novofon_bot
sudo chown novofon_bot:novofon_bot /opt/novofon_bot

# Клонировать/загрузить проект
cd /opt/novofon_bot
# git clone ... или scp файлы

# Создать виртуальное окружение
python3.11 -m venv venv
source venv/bin/activate

# Установить зависимости
pip install --upgrade pip
pip install -r requirements.txt
```

---

### Шаг 4: Настройка PostgreSQL

```bash
# Войти в PostgreSQL
sudo -u postgres psql

# В PostgreSQL консоли:
CREATE DATABASE novofon_bot;
CREATE USER novofon_user WITH PASSWORD 'ваш_надёжный_пароль';
GRANT ALL PRIVILEGES ON DATABASE novofon_bot TO novofon_user;
\q
```

---

### Шаг 5: Создание .env файла

```bash
cd /opt/novofon_bot
nano .env
```

Вставьте (замените значения на ваши):

```env
# Application
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=9000
DEBUG=false

# Database
DATABASE_URL=postgresql+asyncpg://novofon_user:пароль@localhost:5432/novofon_bot

# NovoFon API
NOVOFON_API_KEY=ваш_ключ
NOVOFON_API_URL=https://api.novofon.ru
NOVOFON_FROM_NUMBER=+79991234567

# ElevenLabs
ELEVENLABS_API_KEY=ваш_ключ
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_MODEL=eleven_turbo_v2
ELEVENLABS_AGENT_ID=agent_5701k5f1bymae7ysh9pdwaj0a40h

# ElevenLabs Proxy
ELEVENLABS_PROXY_URL=http://45.85.162.205:8000
ELEVENLABS_PROXY_USERNAME=71cPu3
ELEVENLABS_PROXY_PASSWORD=1XjoMQ

# Asterisk ARI
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=novofon_bot_2024
ASTERISK_ARI_APP_NAME=novofon_bot

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/novofon_bot/app.log
```

Сохраните: `Ctrl+O`, `Enter`, `Ctrl+X`

```bash
# Установить права
chmod 600 .env
```

---

### Шаг 6: Инициализация базы данных

```bash
source venv/bin/activate
python -c "from app.database import init_db; import asyncio; asyncio.run(init_db())"
```

---

### Шаг 7: Установка Asterisk

```bash
# Установить Asterisk
sudo apt install -y asterisk

# Скопировать конфиги
sudo cp asterisk_configs/*.conf /etc/asterisk/

# Настроить SIP данные
sudo nano /etc/asterisk/pjsip.conf
# Замените YOUR_SIP_LOGIN_HERE, YOUR_SIP_PASSWORD_HERE на реальные

# Настроить ARI пароль
sudo nano /etc/asterisk/ari.conf
# Замените пароль на нужный

# Запустить
sudo systemctl start asterisk
sudo systemctl enable asterisk
```

---

### Шаг 8: Systemd сервис

```bash
sudo nano /etc/systemd/system/novofon-bot.service
```

Вставьте:

```ini
[Unit]
Description=NovoFon Voice Bot
After=network.target postgresql.service

[Service]
Type=simple
User=novofon_bot
WorkingDirectory=/opt/novofon_bot
Environment="PATH=/opt/novofon_bot/venv/bin"
ExecStart=/opt/novofon_bot/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 9000 --workers 4
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=novofon-bot

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable novofon-bot
sudo systemctl start novofon-bot
```

---

### Шаг 9: Настройка Nginx

```bash
sudo nano /etc/nginx/sites-available/novofon-bot
```

Вставьте (замените `YOUR_IP_OR_DOMAIN`):

```nginx
server {
    listen 80;
    server_name YOUR_IP_OR_DOMAIN;

    access_log /var/log/nginx/novofon-bot-access.log;
    error_log  /var/log/nginx/novofon-bot-error.log;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/novofon-bot /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

### Шаг 10: Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5060/udp
sudo ufw allow 10000:20000/udp
sudo ufw enable
```

---

## ✅ Проверка установки

```bash
# 1. Статус сервисов
sudo systemctl status novofon-bot
sudo systemctl status asterisk
sudo systemctl status nginx

# 2. Health check
curl http://localhost:9000/health
curl http://YOUR_IP_OR_DOMAIN/health

# 3. Swagger UI
# Откройте в браузере: http://YOUR_IP_OR_DOMAIN/docs

# 4. Логи
sudo journalctl -u novofon-bot -f
```

---

## 📋 Чек-лист установки

- [ ] Система обновлена
- [ ] Python 3.11+ установлен
- [ ] PostgreSQL установлен и настроен
- [ ] Проект загружен в `/opt/novofon_bot`
- [ ] Виртуальное окружение создано
- [ ] Зависимости установлены
- [ ] `.env` файл создан с правильными ключами
- [ ] База данных создана и инициализирована
- [ ] Asterisk установлен и настроен
- [ ] Systemd сервис создан и запущен
- [ ] Nginx настроен
- [ ] Firewall настроен
- [ ] Health check проходит
- [ ] Swagger UI доступен

---

## 🆘 Troubleshooting

### Проблема: Сервис не запускается

```bash
# Проверить логи
sudo journalctl -u novofon-bot -n 100

# Проверить .env
cat /opt/novofon_bot/.env

# Проверить права
ls -la /opt/novofon_bot
```

### Проблема: База данных не подключается

```bash
# Проверить PostgreSQL
sudo systemctl status postgresql

# Проверить подключение
psql -U novofon_user -d novofon_bot -h localhost
```

### Проблема: Nginx не работает

```bash
# Проверить конфиг
sudo nginx -t

# Проверить логи
sudo tail -f /var/log/nginx/error.log
```

---

## 📚 Дополнительная документация

- **Asterisk настройка:** `docs/ASTERISK_SETUP.md`
- **Деплой:** `docs/DEPLOYMENT.md`
- **API тестирование:** `docs/NOVOFON_API_TESTING.md`

---

**Готово!** После выполнения всех шагов у вас будет полностью рабочая система! 🎉

