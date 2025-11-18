#!/bin/bash
# Диагностика проблемы с дозвоном

echo "=========================================="
echo "🔍 Диагностика проблемы с дозвоном"
echo "=========================================="
echo ""

# Проверяем логи Asterisk
echo "1. Последние ошибки в логах Asterisk:"
echo "----------------------------------------"
sudo tail -50 /var/log/asterisk/full | grep -i "error\|fail\|reject\|unreachable" | tail -10

echo ""
echo "2. Последние SIP сообщения:"
echo "----------------------------------------"
sudo tail -50 /var/log/asterisk/full | grep -i "sip\|invite\|200\|403\|404\|487" | tail -10

echo ""
echo "3. Статус endpoint novofon:"
echo "----------------------------------------"
sudo asterisk -rx "pjsip show endpoints" | grep -A 5 novofon

echo ""
echo "4. Проверяем каналы:"
echo "----------------------------------------"
sudo asterisk -rx "core show channels"

echo ""
echo "5. Проверяем SIP трафик (запусти в отдельном терминале):"
echo "   sudo tcpdump -i any -n port 5060 -v | grep -i 'invite\|200\|487\|cancel'"
echo ""

