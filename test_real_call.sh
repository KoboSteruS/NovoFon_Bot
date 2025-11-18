#!/bin/bash
# Тест реального звонка с детальным логированием

echo "=========================================="
echo "📞 Тест реального звонка"
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

# Номер для теста
TEST_PHONE="+79522675444"

info "Инициируем звонок на $TEST_PHONE..."
echo ""

# Делаем запрос и сохраняем ответ
RESPONSE=$(curl -s -X POST http://109.73.192.126/api/calls/initiate \
  -H "Content-Type: application/json" \
  -d "{\"phone\": \"$TEST_PHONE\"}")

echo "Ответ API:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# Извлекаем call_id из ответа
CALL_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('id', ''))" 2>/dev/null)

if [ -n "$CALL_ID" ]; then
    info "Call ID: $CALL_ID"
    echo ""
    
    info "Ждём 5 секунд и проверяем логи бота..."
    sleep 5
    
    echo ""
    info "=== Логи бота (ARI/Call/Originate) ==="
    sudo journalctl -u novofon-bot --since "30 seconds ago" --no-pager | grep -i "call\|originate\|ari\|asterisk\|outgoing\|local" | tail -30 | sed 's/^/   /'
    
    echo ""
    info "=== Логи Asterisk (Dial/Outgoing/Local) ==="
    sudo tail -100 /var/log/asterisk/messages 2>/dev/null | grep -i "outgoing\|dial\|local\|originate\|$CALL_ID" | tail -20 | sed 's/^/   /' || warn "Логи Asterisk не найдены"
    
    echo ""
    info "=== Активные каналы в Asterisk ==="
    sudo asterisk -rx "core show channels" 2>/dev/null | head -10 | sed 's/^/   /'
    
    echo ""
    info "=== Проверка через ARI API ==="
    CHANNELS=$(curl -s -u novofon_bot:62015326495 http://localhost:8088/ari/channels 2>/dev/null | python3 -m json.tool 2>/dev/null | head -30)
    if [ -n "$CHANNELS" ]; then
        echo "$CHANNELS" | sed 's/^/   /'
    else
        warn "Нет активных каналов через ARI"
    fi
else
    error "Не удалось получить Call ID из ответа"
fi

echo ""
info "Тест завершён!"
