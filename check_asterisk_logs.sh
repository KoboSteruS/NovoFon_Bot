#!/bin/bash
# Поиск и проверка логов Asterisk

echo "=========================================="
echo "🔍 Поиск логов Asterisk"
echo "=========================================="
echo ""

# Проверяем возможные места
echo "1. Проверяем стандартные места:"
echo "----------------------------------------"
for log_file in /var/log/asterisk/messages /var/log/asterisk/asterisk.log /var/log/asterisk/full; do
    if [ -f "$log_file" ]; then
        echo "✅ Найден: $log_file"
        echo "   Размер: $(du -h $log_file | cut -f1)"
    fi
done

echo ""
echo "2. Проверяем через journalctl:"
echo "----------------------------------------"
if systemctl is-active --quiet asterisk; then
    echo "✅ Asterisk запущен"
    echo "   Последние логи:"
    sudo journalctl -u asterisk -n 20 --no-pager | tail -10
else
    echo "❌ Asterisk не запущен"
fi

echo ""
echo "3. Проверяем конфигурацию логирования:"
echo "----------------------------------------"
if [ -f /etc/asterisk/logger.conf ]; then
    echo "✅ logger.conf найден"
    grep -E "full|messages|console" /etc/asterisk/logger.conf | head -5
else
    echo "⚠️  logger.conf не найден"
fi

echo ""
echo "4. Проверяем через консоль Asterisk:"
echo "----------------------------------------"
echo "Выполни: sudo asterisk -rvvv"
echo "Затем в консоли: core show channels"
echo ""

