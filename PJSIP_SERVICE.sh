#!/bin/bash
# Скрипт создания systemd сервиса для pjsua клиента
# Используется для обработки звонков через PJSIP WebSocket

set -e

echo "=========================================="
echo "Создание systemd сервиса для pjsua"
echo "=========================================="

# Параметры (можно настроить)
PJSUA_USER="${PJSUA_USER:-root}"
PJSUA_WS_URL="${PJSUA_WS_URL:-ws://127.0.0.1:5066}"
PJSUA_SIP_URI="${PJSUA_SIP_URI:-sip:voicebot@127.0.0.1:5060}"

echo "📝 Создание systemd сервиса..."
cat > /tmp/pjsua.service <<EOF
[Unit]
Description=PJSIP SIP Client (pjsua) with WebSocket
After=network.target asterisk.service
Requires=asterisk.service

[Service]
Type=simple
User=${PJSUA_USER}
WorkingDirectory=/root
ExecStart=/usr/local/bin/pjsua \\
  --log-level=5 \\
  --websocket ${PJSUA_WS_URL} \\
  --no-vad \\
  --auto-answer=200 \\
  ${PJSUA_SIP_URI}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pjsua
Environment="HOME=/root"

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/pjsua.service /etc/systemd/system/pjsua.service
sudo chmod 644 /etc/systemd/system/pjsua.service

echo "✅ systemd сервис создан: /etc/systemd/system/pjsua.service"
echo ""
echo "Для запуска:"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable pjsua"
echo "  sudo systemctl start pjsua"
echo ""
echo "Проверка:"
echo "  sudo systemctl status pjsua"
echo "  sudo journalctl -u pjsua -f"
echo ""



