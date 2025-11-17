#!/bin/bash
# Скрипт автоматического деплоя NovoFon Bot на сервер

set -e  # Остановить при ошибке

echo "=========================================="
echo "🚀 NovoFon Bot - Deployment Script"
echo "=========================================="
echo ""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    error "Пожалуйста, запустите с sudo"
    exit 1
fi

# Переменные
PROJECT_DIR="/opt/novofon_bot"
SERVICE_USER="novofon_bot"
SERVICE_NAME="novofon-bot"

info "Начинаем деплой..."

# Шаг 1: Обновление системы
info "Шаг 1: Обновление системы..."
apt update && apt upgrade -y

# Шаг 2: Установка зависимостей
info "Шаг 2: Установка зависимостей..."
apt install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    postgresql \
    postgresql-contrib \
    git \
    curl \
    build-essential \
    nginx

# Шаг 3: Создание пользователя
info "Шаг 3: Создание пользователя..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -m -s /bin/bash $SERVICE_USER
    info "Пользователь $SERVICE_USER создан"
else
    warn "Пользователь $SERVICE_USER уже существует"
fi

# Шаг 4: Создание директории проекта
info "Шаг 4: Создание директории проекта..."
mkdir -p $PROJECT_DIR
chown $SERVICE_USER:$SERVICE_USER $PROJECT_DIR

# Шаг 5: Копирование файлов (если они в текущей директории)
if [ -f "requirements.txt" ]; then
    info "Шаг 5: Копирование файлов проекта..."
    cp -r . $PROJECT_DIR/
    chown -R $SERVICE_USER:$SERVICE_USER $PROJECT_DIR
else
    warn "Файлы проекта не найдены в текущей директории"
    warn "Пожалуйста, скопируйте файлы вручную в $PROJECT_DIR"
fi

# Шаг 6: Настройка виртуального окружения
info "Шаг 6: Настройка виртуального окружения..."
sudo -u $SERVICE_USER bash <<EOF
cd $PROJECT_DIR
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
EOF

# Шаг 7: Настройка PostgreSQL
info "Шаг 7: Настройка PostgreSQL..."
read -p "Введите пароль для пользователя БД novofon_user: " DB_PASSWORD
sudo -u postgres psql <<EOF
CREATE DATABASE novofon_bot;
CREATE USER novofon_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE novofon_bot TO novofon_user;
EOF

# Шаг 8: Создание .env файла
info "Шаг 8: Создание .env файла..."
if [ ! -f "$PROJECT_DIR/.env" ]; then
    cat > $PROJECT_DIR/.env <<EOF
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=8000
DEBUG=false

DATABASE_URL=postgresql+asyncpg://novofon_user:$DB_PASSWORD@localhost:5432/novofon_bot

NOVOFON_API_KEY=your_key_here
NOVOFON_API_URL=https://api.novofon.ru
NOVOFON_FROM_NUMBER=+79991234567

ELEVENLABS_API_KEY=your_key_here
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_MODEL=eleven_turbo_v2

ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=your_ari_password
ASTERISK_ARI_APP_NAME=novofon_bot

LOG_LEVEL=INFO
LOG_FILE=/var/log/novofon_bot/app.log
EOF
    chmod 600 $PROJECT_DIR/.env
    chown $SERVICE_USER:$SERVICE_USER $PROJECT_DIR/.env
    warn "⚠️  Не забудьте отредактировать $PROJECT_DIR/.env с вашими ключами!"
else
    warn ".env файл уже существует"
fi

# Шаг 9: Создание директории для логов
info "Шаг 9: Создание директории для логов..."
mkdir -p /var/log/novofon_bot
chown $SERVICE_USER:$SERVICE_USER /var/log/novofon_bot

# Шаг 10: Инициализация БД
info "Шаг 10: Инициализация базы данных..."
sudo -u $SERVICE_USER bash <<EOF
cd $PROJECT_DIR
source venv/bin/activate
python -c "from app.database import init_db; import asyncio; asyncio.run(init_db())"
EOF

# Шаг 11: Создание systemd сервиса
info "Шаг 11: Создание systemd сервиса..."
cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=NovoFon Voice Bot
After=network.target postgresql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
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

# Шаг 12: Настройка Nginx
info "Шаг 12: Настройка Nginx..."
read -p "Введите домен или IP для Nginx (или нажмите Enter для пропуска): " DOMAIN

if [ ! -z "$DOMAIN" ]; then
    cat > /etc/nginx/sites-available/$SERVICE_NAME <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    access_log /var/log/nginx/novofon-bot-access.log;
    error_log /var/log/nginx/novofon-bot-error.log;

    location / {
        proxy_pass http://127.0.0.1:8000;
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
    info "Nginx настроен для $DOMAIN"
fi

# Шаг 13: Запуск сервиса
info "Шаг 13: Запуск сервиса..."
systemctl start $SERVICE_NAME
sleep 2
systemctl status $SERVICE_NAME --no-pager

# Финальная проверка
info "Проверка работы..."
sleep 3
if curl -f http://localhost:8000/health > /dev/null 2>&1; then
    info "✅ Health check прошёл успешно!"
else
    error "❌ Health check не прошёл. Проверьте логи: sudo journalctl -u $SERVICE_NAME"
fi

echo ""
echo "=========================================="
info "🎉 Деплой завершён!"
echo "=========================================="
echo ""
echo "Следующие шаги:"
echo "1. Отредактируйте $PROJECT_DIR/.env с вашими API ключами"
echo "2. Перезапустите сервис: sudo systemctl restart $SERVICE_NAME"
echo "3. Проверьте логи: sudo journalctl -u $SERVICE_NAME -f"
echo "4. Откройте Swagger: http://$DOMAIN/docs или http://$(hostname -I | awk '{print $1}'):8000/docs"
echo ""

