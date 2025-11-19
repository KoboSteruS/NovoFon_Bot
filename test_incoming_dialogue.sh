#!/bin/bash
# Тест входящих звонков и диалога

echo "=========================================="
echo "📞 Тест входящих звонков и диалога"
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
    error "Запустите с sudo: sudo bash test_incoming_dialogue.sh"
    exit 1
fi

info "Проверяем настройки для входящих звонков и диалога..."
echo ""

# 1. Проверяем статус бота
info "1. Проверяем статус бота..."
if systemctl is-active --quiet novofon-bot; then
    info "   ✅ Бот запущен"
else
    error "   ❌ Бот НЕ запущен!"
    info "   Запусти: sudo systemctl start novofon-bot"
    exit 1
fi
echo ""

# 2. Проверяем ARI подключение
info "2. Проверяем ARI подключение..."
if journalctl -u novofon-bot -n 50 --no-pager 2>/dev/null | grep -qi "ari.*connected\|asterisk.*connected\|stasis.*connected"; then
    info "   ✅ ARI подключение найдено в логах"
    journalctl -u novofon-bot -n 20 --no-pager 2>/dev/null | grep -i "ari\|asterisk\|stasis\|connected" | tail -5 | sed 's/^/   /'
else
    warn "   ⚠️  ARI подключение НЕ найдено в логах"
    info "   Проверь конфигурацию ARI в .env"
fi
echo ""

# 3. Проверяем логи бота на ошибки
info "3. Проверяем логи бота на ошибки..."
ERRORS=$(journalctl -u novofon-bot -n 100 --no-pager 2>/dev/null | grep -i "error\|exception\|traceback\|failed" | tail -10)
if [ -n "$ERRORS" ]; then
    warn "   ⚠️  Найдены ошибки в логах:"
    echo "$ERRORS" | sed 's/^/   /'
else
    info "   ✅ Ошибок не найдено"
fi
echo ""

# 4. Проверяем обработку входящих звонков
info "4. Проверяем обработку входящих звонков..."
if journalctl -u novofon-bot -n 100 --no-pager 2>/dev/null | grep -qi "incoming\|stasis.*start\|handle.*incoming"; then
    info "   ✅ Обработка входящих звонков найдена в логах"
    journalctl -u novofon-bot -n 50 --no-pager 2>/dev/null | grep -i "incoming\|stasis\|handle.*call" | tail -5 | sed 's/^/   /'
else
    warn "   ⚠️  Обработка входящих звонков не найдена в логах"
fi
echo ""

# 5. Проверяем ElevenLabs подключение
info "5. Проверяем ElevenLabs подключение..."
if journalctl -u novofon-bot -n 100 --no-pager 2>/dev/null | grep -qi "elevenlabs\|voice.*processor\|audio"; then
    info "   ✅ ElevenLabs/voice processor найден в логах"
    journalctl -u novofon-bot -n 50 --no-pager 2>/dev/null | grep -i "elevenlabs\|voice\|audio" | tail -5 | sed 's/^/   /'
else
    warn "   ⚠️  ElevenLabs/voice processor не найден в логах"
    info "   Возможно, диалог не работает из-за проблем с ElevenLabs"
fi
echo ""

# 6. Проверяем FSM (диалог)
info "6. Проверяем FSM (диалог)..."
if journalctl -u novofon-bot -n 100 --no-pager 2>/dev/null | grep -qi "fsm\|dialogue\|greeting\|speak"; then
    info "   ✅ FSM/диалог найден в логах"
    journalctl -u novofon-bot -n 50 --no-pager 2>/dev/null | grep -i "fsm\|dialogue\|greeting\|speak" | tail -5 | sed 's/^/   /'
else
    warn "   ⚠️  FSM/диалог не найден в логах"
    info "   Возможно, диалог не инициализируется"
fi
echo ""

# 7. Проверяем конфигурацию .env
info "7. Проверяем конфигурацию .env..."
if [ -f "/root/NovoFon_Bot/.env" ]; then
    info "   ✅ .env файл найден"
    
    # Проверяем ключевые переменные
    if grep -q "ELEVENLABS" /root/NovoFon_Bot/.env; then
        info "   ✅ ELEVENLABS переменные найдены"
    else
        warn "   ⚠️  ELEVENLABS переменные не найдены"
    fi
    
    if grep -q "ASTERISK_ARI" /root/NovoFon_Bot/.env; then
        info "   ✅ ASTERISK_ARI переменные найдены"
    else
        warn "   ⚠️  ASTERISK_ARI переменные не найдены"
    fi
else
    error "   ❌ .env файл НЕ найден!"
fi
echo ""

# 8. Рекомендации
info "8. Рекомендации для исправления диалога:"
echo ""
info "   Если бот отвечает, но диалога нет:"
info "   1. Проверь, что ElevenLabs настроен правильно в .env"
info "   2. Проверь, что ARI подключение работает"
info "   3. Проверь логи бота в реальном времени:"
info "      sudo journalctl -u novofon-bot -f"
info ""
info "   При входящем звонке должны появиться логи:"
info "   - 'Stasis start: ...'"
info "   - 'Handling incoming call from ...'"
info "   - 'Creating voice processor...'"
info "   - 'Starting dialogue...'"
info "   - 'Speaking: ...' (приветствие)"
echo ""

info "Диагностика завершена!"

