#!/bin/bash
# Тест входящих звонков

echo "=========================================="
echo "📞 Тест входящих звонков"
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
    error "Запустите с sudo: sudo bash test_incoming_call.sh"
    exit 1
fi

info "Проверяем настройки для входящих звонков..."
echo ""

# 1. Проверяем dialplan для входящих
info "1. Проверяем dialplan для входящих звонков..."
if grep -q "^\[from-novofon\]" /etc/asterisk/extensions.conf; then
    info "   ✅ Контекст [from-novofon] найден"
    echo ""
    info "   Содержимое контекста [from-novofon]:"
    sed -n '/^\[from-novofon\]/,/^\[/p' /etc/asterisk/extensions.conf | head -15 | sed 's/^/   /'
else
    error "   ❌ Контекст [from-novofon] НЕ найден!"
    info "   Нужно настроить обработку входящих звонков"
fi
echo ""

# 2. Проверяем ARI приложение
info "2. Проверяем ARI приложение..."
ARI_APP="novofon_bot"
if asterisk -rx "ari show applications" 2>/dev/null | grep -q "$ARI_APP"; then
    info "   ✅ ARI приложение '$ARI_APP' зарегистрировано"
    asterisk -rx "ari show applications" 2>/dev/null | grep "$ARI_APP" | sed 's/^/   /'
else
    warn "   ⚠️  ARI приложение '$ARI_APP' НЕ зарегистрировано"
    info "   Проверь, запущен ли бот и подключён ли он к ARI"
fi
echo ""

# 3. Проверяем endpoint для входящих
info "3. Проверяем endpoint novofon-endpoint для входящих..."
ENDPOINT_CONTEXT=$(asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | grep "Context:" | awk '{print $2}')
if [ -n "$ENDPOINT_CONTEXT" ]; then
    info "   Context endpoint: $ENDPOINT_CONTEXT"
    if [ "$ENDPOINT_CONTEXT" = "from-novofon" ]; then
        info "   ✅ Context правильный (from-novofon)"
    else
        warn "   ⚠️  Context должен быть 'from-novofon', а сейчас: $ENDPOINT_CONTEXT"
    fi
else
    warn "   ⚠️  Context не найден"
fi
echo ""

# 4. Проверяем identify для входящих
info "4. Проверяем identify для входящих звонков..."
if asterisk -rx "pjsip show identifies" 2>/dev/null | grep -q "novofon"; then
    info "   ✅ Identify для NovoFon найден"
    asterisk -rx "pjsip show identifies" 2>/dev/null | grep -A 3 "novofon" | sed 's/^/   /'
else
    warn "   ⚠️  Identify для NovoFon НЕ найден"
    info "   Входящие звонки могут не работать"
fi
echo ""

# 5. Проверяем статус бота
info "5. Проверяем статус бота..."
if systemctl is-active --quiet novofon-bot; then
    info "   ✅ Бот запущен"
    BOT_STATUS=$(systemctl status novofon-bot --no-pager -l | grep -E "Active:|Main PID:" | head -2)
    echo "$BOT_STATUS" | sed 's/^/   /'
else
    error "   ❌ Бот НЕ запущен!"
    info "   Запусти: sudo systemctl start novofon-bot"
fi
echo ""

# 6. Проверяем логи бота на наличие ARI подключения
info "6. Проверяем логи бота на наличие ARI подключения..."
if journalctl -u novofon-bot -n 50 --no-pager 2>/dev/null | grep -qi "ari\|asterisk.*connected\|stasis"; then
    info "   ✅ ARI подключение найдено в логах"
    journalctl -u novofon-bot -n 20 --no-pager 2>/dev/null | grep -i "ari\|asterisk\|stasis" | tail -5 | sed 's/^/   /'
else
    warn "   ⚠️  ARI подключение НЕ найдено в логах"
    info "   Проверь конфигурацию ARI в .env и /etc/asterisk/ari.conf"
fi
echo ""

# 7. Инструкции для теста
info "7. Как протестировать входящий звонок:"
echo ""
info "   Вариант 1: Позвони с телефона на номер, который привязан к NovoFon транку"
info "   Asterisk должен:"
info "   1. Принять входящий звонок через endpoint novofon-endpoint"
info "   2. Направить его в контекст [from-novofon]"
info "   3. Вызвать Stasis приложение 'novofon_bot'"
info "   4. Бот должен обработать звонок через ARI"
echo ""
info "   Вариант 2: Симуляция входящего звонка через Asterisk CLI:"
info "   sudo asterisk -rx \"channel originate PJSIP/novofon-endpoint/100 application Stasis novofon_bot,incoming,100\""
echo ""

# 8. Проверяем, что нужно для работы входящих
info "8. Что нужно для работы входящих звонков:"
echo ""
NEEDS_FIX=0

if ! grep -q "^\[from-novofon\]" /etc/asterisk/extensions.conf; then
    error "   ❌ Нужен контекст [from-novofon] в extensions.conf"
    NEEDS_FIX=1
fi

if ! asterisk -rx "pjsip show identifies" 2>/dev/null | grep -q "novofon"; then
    error "   ❌ Нужен identify для NovoFon в pjsip.conf"
    NEEDS_FIX=1
fi

if ! systemctl is-active --quiet novofon-bot; then
    error "   ❌ Нужен запущенный бот"
    NEEDS_FIX=1
fi

if [ $NEEDS_FIX -eq 0 ]; then
    info "   ✅ Всё настроено для входящих звонков!"
else
    warn "   ⚠️  Есть проблемы, которые нужно исправить"
fi

echo ""
info "Диагностика завершена!"

