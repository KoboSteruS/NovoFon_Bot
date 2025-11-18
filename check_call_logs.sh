#!/bin/bash
# Проверка логов звонков

echo "=========================================="
echo "🔍 Анализ логов Asterisk"
echo "=========================================="
echo ""

echo "1. Последние сообщения о звонках:"
echo "----------------------------------------"
sudo tail -100 /var/log/asterisk/messages | grep -i "call\|dial\|invite\|answer\|hangup" | tail -20

echo ""
echo "2. Ошибки и предупреждения:"
echo "----------------------------------------"
sudo tail -100 /var/log/asterisk/messages | grep -i "error\|warn\|fail" | tail -10

echo ""
echo "3. SIP сообщения:"
echo "----------------------------------------"
sudo tail -100 /var/log/asterisk/messages | grep -i "sip\|pjsip" | tail -15

echo ""
echo "4. Последние 30 строк логов:"
echo "----------------------------------------"
sudo tail -30 /var/log/asterisk/messages

echo ""
echo "5. Для детального анализа сделай звонок и сразу проверь:"
echo "   sudo tail -f /var/log/asterisk/messages"
echo ""

