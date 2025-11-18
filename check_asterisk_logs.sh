#!/bin/bash
# Поиск логов Asterisk

echo "=========================================="
echo "🔍 Поиск логов Asterisk"
echo "=========================================="
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Проверяем стандартные места
info "Проверяем стандартные места для логов..."

for log_path in \
    "/var/log/asterisk/full" \
    "/var/log/asterisk/messages" \
    "/var/log/asterisk/asterisk.log" \
    "/var/log/asterisk/debug" \
    "/var/log/asterisk/verbose" \
    "/usr/local/var/log/asterisk/full" \
    "/usr/local/var/log/asterisk/messages"; do
    if [ -f "$log_path" ]; then
        info "✅ Найден: $log_path"
        echo "   Размер: $(du -h "$log_path" | cut -f1)"
        echo "   Последние 5 строк:"
        tail -5 "$log_path" | sed 's/^/   /'
        echo ""
    fi
done

# Проверяем конфигурацию Asterisk
info "Проверяем конфигурацию логирования..."

if [ -f "/etc/asterisk/logger.conf" ]; then
    info "✅ Файл logger.conf найден"
    echo "   Настройки логирования:"
    grep -E "^full|^messages|^console|^syslog" /etc/asterisk/logger.conf | head -10 | sed 's/^/   /'
    echo ""
fi

# Проверяем через asterisk CLI
info "Проверяем через Asterisk CLI..."

if command -v asterisk &> /dev/null; then
    info "Проверяем статус логирования:"
    asterisk -rx "logger show channels" 2>/dev/null | head -20 || warn "Не удалось получить статус логирования"
    echo ""
    
    info "Проверяем последние события:"
    asterisk -rx "core show settings" 2>/dev/null | grep -i "log\|verbose\|debug" | head -10 || warn "Не удалось получить настройки"
    echo ""
fi

# Проверяем systemd journal
info "Проверяем systemd journal для Asterisk:"
journalctl -u asterisk -n 20 --no-pager 2>/dev/null | tail -10 | sed 's/^/   /' || warn "Не удалось получить journal логи"
echo ""

info "Диагностика завершена!"
