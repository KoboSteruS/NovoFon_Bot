#!/bin/bash
# Тестовый звонок с полным логированием

echo "=========================================="
echo "📞 Тестовый звонок с логированием"
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

# 1. Проверяем, подключен ли ARI к боту
info "1. Проверяем подключение ARI к боту..."
if sudo journalctl -u novofon-bot --since "10 minutes ago" --no-pager | grep -q "ARI connected successfully"; then
    info "✅ ARI подключен к боту"
else
    warn "⚠️  ARI не подключен к боту или не найден в логах"
    echo "   Последние логи бота:"
    sudo journalctl -u novofon-bot -n 30 --no-pager | grep -i "ari\|asterisk" | tail -10 | sed 's/^/   /'
fi
echo ""

# 2. Находим логи Asterisk
info "2. Ищем логи Asterisk..."
ASTERISK_LOG=""
for log_path in \
    "/var/log/asterisk/full" \
    "/var/log/asterisk/messages" \
    "/var/log/asterisk/asterisk.log" \
    "/usr/local/var/log/asterisk/full"; do
    if [ -f "$log_path" ]; then
        ASTERISK_LOG="$log_path"
        info "✅ Найден лог: $log_path"
        break
    fi
done

if [ -z "$ASTERISK_LOG" ]; then
    warn "⚠️  Логи Asterisk не найдены в стандартных местах"
    info "   Проверяем через Asterisk CLI..."
    sudo asterisk -rx "logger show channels" 2>/dev/null | head -10
fi
echo ""

# 3. Включаем verbose логирование в Asterisk (если нужно)
info "3. Проверяем уровень логирования Asterisk..."
VERBOSE_LEVEL=$(sudo asterisk -rx "core show settings" 2>/dev/null | grep "Default verbosity" | awk '{print $3}')
if [ -n "$VERBOSE_LEVEL" ]; then
    info "   Уровень verbose: $VERBOSE_LEVEL"
    if [ "$VERBOSE_LEVEL" -lt 3 ]; then
        warn "   Рекомендуется увеличить до 3 для отладки"
        info "   Команда: sudo asterisk -rx 'core set verbose 3'"
    fi
fi
echo ""

# 4. Запускаем мониторинг логов в фоне
info "4. Запускаем мониторинг логов..."
if [ -n "$ASTERISK_LOG" ]; then
    info "   Мониторинг: $ASTERISK_LOG"
    (sudo tail -f "$ASTERISK_LOG" 2>/dev/null | grep -i "outgoing\|novofon\|dial\|local\|pjsip" &) &
    TAIL_PID=$!
    sleep 2
else
    info "   Мониторинг через Asterisk CLI..."
    (sudo asterisk -rvvv 2>&1 | grep -i "outgoing\|novofon\|dial\|local\|pjsip" &) &
    TAIL_PID=$!
    sleep 2
fi

# 5. Мониторинг логов бота
info "5. Мониторинг логов бота..."
(sudo journalctl -u novofon-bot -f --no-pager | grep -i "call\|initiate\|ari\|asterisk" &) &
BOT_TAIL_PID=$!
sleep 2

# 6. Делаем тестовый звонок
info "6. Делаем тестовый звонок..."
echo ""
read -p "Введи номер для теста (или Enter для +79522675444): " TEST_PHONE
TEST_PHONE=${TEST_PHONE:-+79522675444}

info "Инициируем звонок на $TEST_PHONE..."
RESPONSE=$(curl -s -X POST http://109.73.192.126/api/calls/initiate \
  -H "Content-Type: application/json" \
  -d "{\"phone\": \"$TEST_PHONE\"}")

echo ""
info "Ответ API:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# 7. Ждём 10 секунд и смотрим логи
info "7. Ждём 10 секунд и смотрим логи..."
sleep 10

# 8. Останавливаем мониторинг
info "8. Останавливаем мониторинг..."
kill $TAIL_PID 2>/dev/null || true
kill $BOT_TAIL_PID 2>/dev/null || true

# 9. Показываем последние логи
info "9. Последние логи бота (ARI/Call):"
sudo journalctl -u novofon-bot --since "1 minute ago" --no-pager | grep -i "call\|initiate\|ari\|asterisk\|outgoing\|local" | tail -20 | sed 's/^/   /'
echo ""

if [ -n "$ASTERISK_LOG" ]; then
    info "10. Последние логи Asterisk (SIP/Dial):"
    sudo tail -50 "$ASTERISK_LOG" 2>/dev/null | grep -i "outgoing\|novofon\|dial\|local\|pjsip" | tail -20 | sed 's/^/   /'
else
    info "10. Проверяем активные каналы в Asterisk:"
    sudo asterisk -rx "core show channels" 2>/dev/null | head -10 | sed 's/^/   /'
fi
echo ""

info "Тест завершён!"

