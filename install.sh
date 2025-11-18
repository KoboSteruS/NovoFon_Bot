#!/bin/bash
# Полная установка NovoFon Voice Bot на чистый сервер
# Автоматическая установка всех компонентов

set -e  # Остановить при ошибке

echo "=========================================="
echo "🚀 NovoFon Voice Bot - Полная установка"
echo "=========================================="
echo ""

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    error "Запустите с sudo: sudo bash install.sh"
    exit 1
fi

# Переменные
PROJECT_DIR="/opt/novofon_bot"
SERVICE_USER="novofon_bot"
SERVICE_NAME="novofon-bot"
DB_NAME="novofon_bot"
DB_USER="novofon_user"

info "Начинаем установку..."
echo ""

# ==========================================
# ШАГ 1: Обновление системы
# ==========================================
info "Шаг 1: Обновление системы..."
apt update && apt upgrade -y
info "✅ Система обновлена"
echo ""

# ==========================================
# ШАГ 2: Установка базовых зависимостей
# ==========================================
info "Шаг 2: Установка базовых зависимостей..."
apt install -y \
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
    ufw \
    software-properties-common

info "✅ Зависимости установлены"
echo ""

# ==========================================
# ШАГ 3: Создание пользователя
# ==========================================
info "Шаг 3: Создание пользователя для бота..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -m -s /bin/bash $SERVICE_USER
    info "✅ Пользователь $SERVICE_USER создан"
else
    warn "Пользователь $SERVICE_USER уже существует"
fi
echo ""

# ==========================================
# ШАГ 4: Создание директории проекта
# ==========================================
info "Шаг 4: Создание директории проекта..."
mkdir -p $PROJECT_DIR
chown $SERVICE_USER:$SERVICE_USER $PROJECT_DIR
info "✅ Директория создана: $PROJECT_DIR"
echo ""

# ==========================================
# ШАГ 5: Копирование проекта
# ==========================================
info "Шаг 5: Копирование файлов проекта..."
if [ -f "requirements.txt" ]; then
    cp -r . $PROJECT_DIR/
    chown -R $SERVICE_USER:$SERVICE_USER $PROJECT_DIR
    info "✅ Файлы скопированы"
else
    warn "⚠️  Файлы проекта не найдены в текущей директории"
    warn "   Скопируйте файлы вручную в $PROJECT_DIR"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# ==========================================
# ШАГ 6: Установка Python зависимостей
# ==========================================
info "Шаг 6: Установка Python зависимостей..."
sudo -u $SERVICE_USER bash <<EOF
cd $PROJECT_DIR
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
EOF
info "✅ Python зависимости установлены"
echo ""

# ==========================================
# ШАГ 7: Настройка PostgreSQL
# ==========================================
info "Шаг 7: Настройка PostgreSQL..."
read -sp "Введите пароль для пользователя БД $DB_USER: " DB_PASSWORD
echo ""

sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
\q
EOF

info "✅ База данных создана"
echo ""

# ==========================================
# ШАГ 8: Создание .env файла
# ==========================================
info "Шаг 8: Создание .env файла..."
read -p "NovoFon API Key: " NOVOFON_KEY
read -p "NovoFon номер (например +79991234567): " NOVOFON_NUMBER
read -p "ElevenLabs API Key: " ELEVENLABS_KEY
read -p "ElevenLabs Agent ID (опционально): " ELEVENLABS_AGENT
read -p "ElevenLabs Proxy URL (опционально): " ELEVENLABS_PROXY
read -p "ElevenLabs Proxy Username (опционально): " ELEVENLABS_PROXY_USER
read -p "ElevenLabs Proxy Password (опционально): " ELEVENLABS_PROXY_PASS

cat > $PROJECT_DIR/.env <<EOF
# Application
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=9000
DEBUG=false

# Database
DATABASE_URL=postgresql+asyncpg://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME

# NovoFon API
NOVOFON_API_KEY=$NOVOFON_KEY
NOVOFON_API_URL=https://api.novofon.ru
NOVOFON_FROM_NUMBER=$NOVOFON_NUMBER

# ElevenLabs
ELEVENLABS_API_KEY=$ELEVENLABS_KEY
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_MODEL=eleven_turbo_v2
ELEVENLABS_AGENT_ID=$ELEVENLABS_AGENT

# ElevenLabs Proxy
ELEVENLABS_PROXY_URL=$ELEVENLABS_PROXY
ELEVENLABS_PROXY_USERNAME=$ELEVENLABS_PROXY_USER
ELEVENLABS_PROXY_PASSWORD=$ELEVENLABS_PROXY_PASS

# Asterisk ARI
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=novofon_bot_2024
ASTERISK_ARI_APP_NAME=novofon_bot

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/novofon_bot/app.log
EOF

chmod 600 $PROJECT_DIR/.env
chown $SERVICE_USER:$SERVICE_USER $PROJECT_DIR/.env
info "✅ .env файл создан"
echo ""

# ==========================================
# ШАГ 9: Инициализация базы данных
# ==========================================
info "Шаг 9: Инициализация базы данных..."
sudo -u $SERVICE_USER bash <<EOF
cd $PROJECT_DIR
source venv/bin/activate
python -c "from app.database import init_db; import asyncio; asyncio.run(init_db())"
EOF
info "✅ База данных инициализирована"
echo ""

# ==========================================
# ШАГ 10: Создание директории для логов
# ==========================================
info "Шаг 10: Создание директории для логов..."
mkdir -p /var/log/novofon_bot
chown $SERVICE_USER:$SERVICE_USER /var/log/novofon_bot
info "✅ Директория логов создана"
echo ""

# ==========================================
# ШАГ 11: Установка Asterisk
# ==========================================
info "Шаг 11: Установка Asterisk..."
read -p "Установить Asterisk? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt install -y asterisk
    
    # Копирование конфигов
    if [ -d "$PROJECT_DIR/asterisk_configs" ]; then
        cp $PROJECT_DIR/asterisk_configs/*.conf /etc/asterisk/
        chown asterisk:asterisk /etc/asterisk/*.conf
        chmod 640 /etc/asterisk/*.conf
        info "✅ Конфиги Asterisk скопированы"
        warn "⚠️  Не забудьте настроить SIP данные в /etc/asterisk/pjsip.conf"
    fi
    
    systemctl start asterisk
    systemctl enable asterisk
    info "✅ Asterisk установлен и запущен"
else
    warn "Asterisk пропущен (можно установить позже)"
fi
echo ""

# ==========================================
# ШАГ 12: Создание systemd сервиса
# ==========================================
info "Шаг 12: Создание systemd сервиса..."
cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=NovoFon Voice Bot
After=network.target postgresql.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 9000 --workers 4
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
info "✅ Systemd сервис создан"
echo ""

# ==========================================
# ШАГ 13: Настройка Nginx
# ==========================================
info "Шаг 13: Настройка Nginx..."
read -p "Введите домен или IP для Nginx: " DOMAIN_OR_IP

cat > /etc/nginx/sites-available/$SERVICE_NAME <<EOF
server {
    listen 80;
    server_name $DOMAIN_OR_IP;

    access_log /var/log/nginx/novofon-bot-access.log;
    error_log  /var/log/nginx/novofon-bot-error.log;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
info "✅ Nginx настроен"
echo ""

# ==========================================
# ШАГ 14: Настройка Firewall
# ==========================================
info "Шаг 14: Настройка Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 5060/udp
ufw allow 10000:20000/udp
info "✅ Firewall настроен"
echo ""

# ==========================================
# ШАГ 15: Запуск сервиса
# ==========================================
info "Шаг 15: Запуск бота..."
systemctl start $SERVICE_NAME
sleep 3
systemctl status $SERVICE_NAME --no-pager | head -20
echo ""

# ==========================================
# ФИНАЛЬНАЯ ПРОВЕРКА
# ==========================================
info "Проверка работы..."
sleep 2

if curl -f http://localhost:9000/health > /dev/null 2>&1; then
    info "✅ Health check прошёл успешно!"
else
    error "❌ Health check не прошёл. Проверьте логи: sudo journalctl -u $SERVICE_NAME"
fi

echo ""
echo "=========================================="
info "🎉 Установка завершена!"
echo "=========================================="
echo ""
echo "📋 Следующие шаги:"
echo ""
echo "1. Настройте Asterisk SIP транк (если установлен):"
echo "   sudo nano /etc/asterisk/pjsip.conf"
echo ""
echo "2. Проверьте логи:"
echo "   sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "3. Откройте Swagger UI:"
echo "   http://$DOMAIN_OR_IP/docs"
echo ""
echo "4. Проверьте статус всех сервисов:"
echo "   sudo systemctl status $SERVICE_NAME"
echo "   sudo systemctl status asterisk"
echo "   sudo systemctl status nginx"
echo ""
echo "=========================================="

