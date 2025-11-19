#!/bin/bash
# Тест реального SIP трафика

echo "=========================================="
echo "📡 Тест реального SIP трафика"
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
    error "Запустите с sudo: sudo bash test_sip_traffic.sh"
    exit 1
fi

info "Запускаем детальный мониторинг SIP трафика..."
echo ""

# Очищаем старые логи
truncate -s 0 /var/log/asterisk/messages 2>/dev/null || true

# Запускаем tcpdump в фоне с полным выводом
info "Запускаем tcpdump для мониторинга SIP трафика..."
(sudo tcpdump -i any -n -s 0 -X port 5060 2>&1 | tee /tmp/sip_traffic.log &) &
TCPDUMP_PID=$!
sleep 2
info "✅ Мониторинг запущен (PID: $TCPDUMP_PID)"
echo ""

# Делаем тестовый звонок
info "Делаем тестовый звонок..."
asterisk -rx "channel originate Local/79522675444@outgoing application Playback hello-world" 2>&1 | head -3

# Ждём 10 секунд
info "Ждём 10 секунд..."
sleep 10

# Останавливаем tcpdump
kill $TCPDUMP_PID 2>/dev/null || true
sleep 1

# Анализируем трафик
info "Анализируем SIP трафик..."
echo ""

info "Исходящие пакеты к sip.novofon.ru:"
if grep -i "sip.novofon.ru" /tmp/sip_traffic.log | grep -i "out\|>" | head -10; then
    info "✅ Найдены исходящие пакеты к sip.novofon.ru"
else
    error "❌ Исходящие пакеты к sip.novofon.ru НЕ найдены!"
fi
echo ""

info "INVITE запросы:"
if grep -i "INVITE" /tmp/sip_traffic.log | head -5; then
    info "✅ INVITE запросы найдены"
else
    error "❌ INVITE запросы НЕ найдены!"
fi
echo ""

info "Полный SIP трафик (первые 50 строк):"
head -50 /tmp/sip_traffic.log | sed 's/^/   /'
echo ""

info "Логи Asterisk:"
tail -50 /var/log/asterisk/messages 2>/dev/null | grep -E "79522675444|outgoing|Dial|PJSIP|novofon|INVITE" | tail -20 | sed 's/^/   /' || warn "Логи не найдены"

echo ""
info "Тест завершён!"
info "Полный лог сохранён в /tmp/sip_traffic.log"

