#!/bin/bash
# Скрипт для проверки и тестового звонка через NovoFon

echo "=========================================="
echo "🔍 Проверка конфигурации Asterisk"
echo "=========================================="

# Проверяем endpoint
echo ""
echo "1. Проверяем endpoint novofon:"
sudo asterisk -rx "pjsip show endpoints" | grep -A 5 novofon

echo ""
echo "2. Проверяем AOR:"
sudo asterisk -rx "pjsip show aors" | grep -A 3 novofon

echo ""
echo "3. Проверяем auth:"
sudo asterisk -rx "pjsip show auths" | grep -A 3 novofon

echo ""
echo "4. Проверяем регистрацию (если есть):"
sudo asterisk -rx "pjsip show registrations"

echo ""
echo "=========================================="
echo "📞 Тестовый звонок"
echo "=========================================="
echo ""
read -p "Введи номер для теста (например +79991234567): " TEST_NUMBER

# Убираем + и пробелы
TEST_NUMBER=$(echo $TEST_NUMBER | tr -d '+ ')

echo ""
echo "Делаю звонок на $TEST_NUMBER..."
echo "Слушай SIP трафик в отдельном терминале: sudo tcpdump -i any -n port 5060 -v"
echo ""

# Используем Dial() для реального звонка
sudo asterisk -rx "channel originate Local/${TEST_NUMBER}@outgoing application Playback hello-world" || \
sudo asterisk -rx "channel originate PJSIP/${TEST_NUMBER}@novofon extension s@outgoing"

echo ""
echo "Проверь логи: sudo tail -f /var/log/asterisk/full"

