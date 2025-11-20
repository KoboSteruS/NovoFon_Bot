#!/bin/bash
# Скрипт установки и настройки baresip для NovoFon Bot

set -e

echo "=========================================="
echo "Установка Baresip для NovoFon Bot"
echo "=========================================="

# 1. Установка baresip
echo "📦 Установка baresip..."
sudo apt update
sudo apt install -y baresip baresip-mod-websocket baresip-mod-httpreq

# 2. Создание директории конфигурации
echo "📁 Создание директории конфигурации..."
mkdir -p ~/.baresip

# 3. Копирование конфигурационных файлов
echo "📋 Копирование конфигурационных файлов..."
if [ -f "baresip_configs/config" ]; then
    cp baresip_configs/config ~/.baresip/config
    chmod 644 ~/.baresip/config
    echo "✅ Конфиг скопирован"
else
    echo "❌ Файл baresip_configs/config не найден!"
    exit 1
fi

if [ -f "baresip_configs/accounts" ]; then
    cp baresip_configs/accounts ~/.baresip/accounts
    chmod 644 ~/.baresip/accounts
    echo "✅ Accounts скопирован"
else
    echo "❌ Файл baresip_configs/accounts не найден!"
    exit 1
fi

# 4. Создание systemd сервиса
echo "🔧 Создание systemd сервиса..."
sudo tee /etc/systemd/system/baresip.service > /dev/null <<EOF
[Unit]
Description=Baresip SIP Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/baresip
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=baresip

[Install]
WantedBy=multi-user.target
EOF

# 5. Включение и запуск сервиса
echo "🚀 Запуск baresip..."
sudo systemctl daemon-reload
sudo systemctl enable baresip
sudo systemctl start baresip

# 6. Проверка статуса
echo "✅ Проверка статуса..."
sleep 2
sudo systemctl status baresip --no-pager

echo ""
echo "=========================================="
echo "✅ Baresip установлен и запущен!"
echo "=========================================="
echo ""
echo "Проверка работы:"
echo "  sudo systemctl status baresip"
echo "  sudo journalctl -u baresip -f"
echo ""
echo "Проверка WebSocket:"
echo "  netstat -tlnp | grep 8000"
echo ""

