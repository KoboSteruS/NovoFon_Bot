#!/bin/bash
# Детальная диагностика SIP Dial

echo "=========================================="
echo "🔍 Детальная диагностика SIP Dial"
echo "=========================================="
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Включаем детальное логирование
info "1. Включаем детальное логирование Asterisk..."
sudo asterisk -rx "core set verbose 5" > /dev/null 2>&1
sudo asterisk -rx "core set debug 1" > /dev/null 2>&1
sudo asterisk -rx "pjsip set logger on" > /dev/null 2>&1
info "✅ Логирование включено"
echo ""

# 2. Очищаем старые логи (чтобы видеть только новые)
info "2. Очищаем старые логи..."
sudo truncate -s 0 /var/log/asterisk/messages 2>/dev/null || true
info "✅ Логи очищены"
echo ""

# 3. Запускаем мониторинг SIP трафика в фоне
info "3. Запускаем мониторинг SIP трафика..."
(sudo tcpdump -i any -n port 5060 -v -c 50 2>&1 | grep -i "invite\|200\|401\|403\|sip.novofon" &) &
TCPDUMP_PID=$!
sleep 2
info "✅ Мониторинг запущен (PID: $TCPDUMP_PID)"
echo ""

# 4. Делаем тестовый звонок через Asterisk CLI
info "4. Делаем тестовый звонок через Asterisk CLI..."
echo "   Команда: channel originate Local/79522675444@outgoing application Playback hello-world"
echo ""

# Делаем звонок
sudo asterisk -rx "channel originate Local/79522675444@outgoing application Playback hello-world" 2>&1 | head -5

# Ждём 5 секунд
sleep 5

# Останавливаем tcpdump
kill $TCPDUMP_PID 2>/dev/null || true
sleep 1

# 5. Смотрим логи Asterisk
info "5. Логи Asterisk (Dial/PJSIP/NovoFon):"
sudo tail -100 /var/log/asterisk/messages 2>/dev/null | grep -i "dial\|pjsip\|novofon\|79522675444\|invite\|outgoing" | tail -30 | sed 's/^/   /' || warn "Логи не найдены"
echo ""

# 6. Проверяем, что произошло с каналом
info "6. Проверяем активные каналы:"
sudo asterisk -rx "core show channels" 2>/dev/null | head -10 | sed 's/^/   /'
echo ""

# 7. Проверяем PJSIP детально
info "7. Детальная информация о PJSIP endpoint novofon:"
sudo asterisk -rx "pjsip show endpoint novofon" 2>/dev/null | head -30 | sed 's/^/   /'
echo ""

# 8. Проверяем, может ли Asterisk разрешить номер
info "8. Проверяем разрешение номера через PJSIP:"
sudo asterisk -rx "pjsip show endpoint 79522675444@novofon" 2>/dev/null | head -20 | sed 's/^/   /' || warn "Не удалось разрешить номер"
echo ""

# Выключаем детальное логирование
sudo asterisk -rx "core set verbose 0" > /dev/null 2>&1
sudo asterisk -rx "core set debug 0" > /dev/null 2>&1
sudo asterisk -rx "pjsip set logger off" > /dev/null 2>&1

info "Диагностика завершена!"


