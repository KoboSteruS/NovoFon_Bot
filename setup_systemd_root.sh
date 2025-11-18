#!/bin/bash
# Настройка systemd service для бота в /root/NovoFon_Bot

set -e

echo "=========================================="
echo "🔧 Настройка systemd service в /root/NovoFon_Bot"
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
    error "Запустите с sudo: sudo bash setup_systemd_root.sh"
    exit 1
fi

PROJECT_DIR="/root/NovoFon_Bot"
SERVICE_NAME="novofon-bot"

# Проверяем, что проект существует
if [ ! -d "$PROJECT_DIR" ]; then
    error "Директория $PROJECT_DIR не найдена!"
    exit 1
fi

info "Проект найден: $PROJECT_DIR"

# Проверяем venv
if [ ! -d "$PROJECT_DIR/venv" ]; then
    warn "venv не найден, создаём..."
    cd $PROJECT_DIR
    python3.11 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
    info "✅ venv создан"
else
    info "✅ venv найден"
fi

# Создаём systemd service
info "Создаём systemd service..."

cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=NovoFon Voice Bot
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
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
info "✅ Systemd service создан"

# Проверяем .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    warn ".env не найден, создаём из your_env_config.txt..."
    if [ -f "$PROJECT_DIR/your_env_config.txt" ]; then
        cp $PROJECT_DIR/your_env_config.txt $PROJECT_DIR/.env
        info "✅ .env создан из your_env_config.txt"
    else
        warn "⚠️  your_env_config.txt не найден, создайте .env вручную"
    fi
fi

# Обновляем websockets в venv
info "Обновляем websockets в venv..."
cd $PROJECT_DIR
source venv/bin/activate
pip uninstall websockets -y
pip install websockets==10.4
deactivate
info "✅ websockets обновлён"

echo ""
info "✅ Настройка завершена!"
echo ""
info "Следующие шаги:"
info "1. Проверь .env: nano $PROJECT_DIR/.env"
info "2. Запусти бота: sudo systemctl start $SERVICE_NAME"
info "3. Проверь статус: sudo systemctl status $SERVICE_NAME"
info "4. Проверь логи: sudo journalctl -u $SERVICE_NAME -f"
echo ""

