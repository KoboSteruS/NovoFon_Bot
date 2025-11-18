#!/bin/bash
# Проверка подключения ARI к боту

echo "=========================================="
echo "🔍 Проверка подключения ARI"
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

# 1. Проверяем логи бота на наличие ARI подключения
info "1. Проверяем подключение ARI к боту..."
ARI_CONNECTED=$(sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -i "ARI connected successfully" | tail -1)
ARI_ERROR=$(sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -i "ARI not available\|ARI.*error\|ARI.*fail" | tail -1)

if [ -n "$ARI_CONNECTED" ]; then
    info "✅ ARI подключен к боту"
    echo "   $ARI_CONNECTED" | sed 's/^/   /'
elif [ -n "$ARI_ERROR" ]; then
    error "❌ ARI не подключен:"
    echo "   $ARI_ERROR" | sed 's/^/   /'
    echo ""
    info "   Полная ошибка:"
    sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -A 5 -i "ARI not available\|ARI.*error" | tail -10 | sed 's/^/   /'
else
    warn "⚠️  Не найдено информации о подключении ARI"
    info "   Последние логи бота при запуске:"
    sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -i "starting\|ARI\|asterisk" | head -10 | sed 's/^/   /'
fi
echo ""

# 2. Проверяем, что ARI доступен
info "2. Проверяем доступность ARI..."
if curl -s -u novofon_bot:62015326495 http://localhost:8088/ari/asterisk/info > /dev/null 2>&1; then
    info "✅ ARI доступен на localhost:8088"
    ARI_INFO=$(curl -s -u novofon_bot:62015326495 http://localhost:8088/ari/asterisk/info | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"Asterisk {d.get('system', {}).get('version', 'unknown')}\")" 2>/dev/null)
    if [ -n "$ARI_INFO" ]; then
        info "   $ARI_INFO"
    fi
else
    error "❌ ARI недоступен на localhost:8088"
    info "   Проверь:"
    info "   - Запущен ли Asterisk: sudo systemctl status asterisk"
    info "   - Настроен ли ARI: sudo cat /etc/asterisk/ari.conf"
fi
echo ""

# 3. Проверяем зарегистрированные ARI приложения
info "3. Проверяем зарегистрированные ARI приложения..."
ARI_APPS=$(sudo asterisk -rx "ari show apps" 2>/dev/null)
if echo "$ARI_APPS" | grep -q "novofon_bot"; then
    info "✅ Приложение novofon_bot зарегистрировано в ARI"
    echo "$ARI_APPS" | sed 's/^/   /'
else
    warn "⚠️  Приложение novofon_bot не найдено в ARI"
    echo "$ARI_APPS" | sed 's/^/   /'
fi
echo ""

# 4. Проверяем последние попытки звонков
info "4. Проверяем последние попытки звонков..."
CALL_ATTEMPTS=$(sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -i "initiate\|originate\|call.*to" | tail -10)
if [ -n "$CALL_ATTEMPTS" ]; then
    info "Найдены попытки звонков:"
    echo "$CALL_ATTEMPTS" | sed 's/^/   /'
else
    warn "Не найдено попыток звонков за последний час"
fi
echo ""

# 5. Проверяем, использует ли бот ARI или падает на NovoFon API
info "5. Проверяем, какой метод использует бот для звонков..."
LAST_CALL=$(sudo journalctl -u novofon-bot --since "1 hour ago" --no-pager | grep -i "initiate\|call.*via" | tail -5)
if echo "$LAST_CALL" | grep -q "Asterisk\|ARI"; then
    info "✅ Бот использует Asterisk/ARI для звонков"
elif echo "$LAST_CALL" | grep -q "NovoFon API\|novofon"; then
    warn "⚠️  Бот использует NovoFon API (fallback) вместо Asterisk"
    info "   Это означает, что ARI не работает или не подключен"
else
    warn "⚠️  Не найдено информации о методе звонков"
fi
echo ""

info "Диагностика завершена!"

