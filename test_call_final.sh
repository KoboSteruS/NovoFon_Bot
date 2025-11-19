#!/bin/bash
# Финальный тест звонка после исправления

echo "=========================================="
echo "📞 Финальный тест звонка"
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
    error "Запустите с sudo: sudo bash test_call_final.sh"
    exit 1
fi

# 1. Проверяем конфигурацию
info "1. Проверяем конфигурацию..."
echo ""

info "   PJSIP endpoints:"
ENDPOINTS=$(asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -i "novofon")
if [ -n "$ENDPOINTS" ]; then
    echo "$ENDPOINTS" | sed 's/^/   /'
    info "   ✅ Endpoint novofon найден"
else
    error "   ❌ Endpoint novofon НЕ НАЙДЕН!"
    exit 1
fi
echo ""

info "   Dialplan [outgoing]:"
DIAL_CHECK=$(asterisk -rx "dialplan show outgoing" 2>/dev/null | grep -i "Dial.*novofon")
if [ -n "$DIAL_CHECK" ]; then
    echo "$DIAL_CHECK" | sed 's/^/   /'
    info "   ✅ Dial() с novofon найден"
else
    error "   ❌ Dial() с novofon НЕ НАЙДЕН!"
    exit 1
fi
echo ""

# 2. Включаем логирование
info "2. Включаем детальное логирование..."
asterisk -rx "core set verbose 5" > /dev/null 2>&1
asterisk -rx "core set debug 1" > /dev/null 2>&1
info "✅ Логирование включено"
echo ""

# 3. Очищаем логи
info "3. Очищаем старые логи..."
truncate -s 0 /var/log/asterisk/messages 2>/dev/null || true
info "✅ Логи очищены"
echo ""

# 4. Запускаем мониторинг SIP трафика
info "4. Запускаем мониторинг SIP трафика..."
(sudo tcpdump -i any -n port 5060 -v -c 30 2>&1 | grep -E "INVITE|200|ACK|BYE|sip.novofon|79522675444" &) &
TCPDUMP_PID=$!
sleep 2
info "✅ Мониторинг запущен (PID: $TCPDUMP_PID)"
echo ""

# 5. Делаем тестовый звонок
info "5. Делаем тестовый звонок через Asterisk CLI..."
echo "   Команда: channel originate Local/79522675444@outgoing application Playback hello-world"
echo ""

asterisk -rx "channel originate Local/79522675444@outgoing application Playback hello-world" 2>&1 | head -3

# Ждём 8 секунд
info "   Ждём 8 секунд для полного цикла..."
sleep 8

# Останавливаем tcpdump
kill $TCPDUMP_PID 2>/dev/null || true
sleep 1

# 6. Проверяем логи
info "6. Логи Asterisk (последние 50 строк с ключевыми словами):"
tail -200 /var/log/asterisk/messages 2>/dev/null | grep -E "79522675444|outgoing|Dial|PJSIP|novofon|INVITE|200|BYE|hangup" | tail -30 | sed 's/^/   /' || warn "Логи не найдены"
echo ""

# 7. Проверяем активные каналы
info "7. Проверяем активные каналы:"
asterisk -rx "core show channels" 2>/dev/null | head -10 | sed 's/^/   /'
echo ""

# 8. Проверяем, был ли INVITE к sip.novofon.ru
info "8. Проверяем, был ли INVITE к sip.novofon.ru..."
if tail -200 /var/log/asterisk/messages 2>/dev/null | grep -q "sip.novofon.ru"; then
    info "   ✅ INVITE к sip.novofon.ru найден в логах!"
else
    warn "   ⚠️  INVITE к sip.novofon.ru НЕ найден в логах"
    warn "   Возможно, звонок всё ещё не уходит наружу"
fi
echo ""

# Выключаем логирование
asterisk -rx "core set verbose 0" > /dev/null 2>&1
asterisk -rx "core set debug 0" > /dev/null 2>&1

info "Тест завершён!"
echo ""
info "Если в логах видно INVITE к sip.novofon.ru - значит звонок уходит наружу!"
info "Если нет - проверь конфигурацию ещё раз."

