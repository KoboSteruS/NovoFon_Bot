#!/bin/bash
# Детальная диагностика полного цикла звонка

echo "=========================================="
echo "🔍 Детальная диагностика полного цикла звонка"
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

# 1. Включаем максимальное логирование
info "1. Включаем максимальное логирование..."
sudo asterisk -rx "core set verbose 10" > /dev/null 2>&1
sudo asterisk -rx "core set debug 3" > /dev/null 2>&1
sudo asterisk -rx "pjsip set logger on" > /dev/null 2>&1
sudo asterisk -rx "rtp set debug on" > /dev/null 2>&1
info "✅ Логирование включено"
echo ""

# 2. Очищаем логи
info "2. Очищаем логи..."
sudo truncate -s 0 /var/log/asterisk/messages 2>/dev/null || true
info "✅ Логи очищены"
echo ""

# 3. Запускаем мониторинг RTP трафика
info "3. Запускаем мониторинг RTP трафика (порты 10000-20000)..."
(sudo tcpdump -i any -n "udp portrange 10000-20000" -c 20 -v 2>&1 | grep -E "RTP|rtp|udp.*>" &) &
RTP_PID=$!
sleep 1
info "✅ Мониторинг RTP запущен (PID: $RTP_PID)"
echo ""

# 4. Запускаем мониторинг SIP трафика
info "4. Запускаем мониторинг SIP трафика..."
(sudo tcpdump -i any -n port 5060 -v -c 30 2>&1 | grep -E "INVITE|200|ACK|BYE|CANCEL|487|488|RTP" &) &
SIP_PID=$!
sleep 1
info "✅ Мониторинг SIP запущен (PID: $SIP_PID)"
echo ""

# 5. Делаем тестовый звонок
info "5. Делаем тестовый звонок..."
echo "   Команда: channel originate Local/79522675444@outgoing application Playback hello-world"
echo ""

sudo asterisk -rx "channel originate Local/79522675444@outgoing application Playback hello-world" 2>&1 | head -3

# Ждём 10 секунд для полного цикла
info "   Ждём 10 секунд для полного цикла..."
sleep 10

# Останавливаем мониторинг
kill $RTP_PID 2>/dev/null || true
kill $SIP_PID 2>/dev/null || true
sleep 1

# 6. Смотрим логи Asterisk
info "6. Логи Asterisk (полный цикл):"
sudo tail -200 /var/log/asterisk/messages 2>/dev/null | grep -E "79522675444|outgoing|Dial|PJSIP|RTP|SDP|media|audio|channel|hangup|BYE|CANCEL" | tail -50 | sed 's/^/   /' || warn "Логи не найдены"
echo ""

# 7. Проверяем статус каналов
info "7. Проверяем активные каналы:"
sudo asterisk -rx "core show channels" 2>/dev/null | head -15 | sed 's/^/   /'
echo ""

# 8. Проверяем RTP статистику
info "8. Проверяем RTP статистику:"
sudo asterisk -rx "rtp show stats" 2>/dev/null | head -20 | sed 's/^/   /' || warn "RTP статистика недоступна"
echo ""

# 9. Проверяем формат номера в dialplan
info "9. Проверяем формат номера в dialplan:"
sudo asterisk -rx "dialplan show outgoing" 2>/dev/null | grep -A 10 "outgoing" | sed 's/^/   /'
echo ""

# 10. Проверяем, какой номер отправляется в INVITE
info "10. Проверяем последние SIP сообщения:"
sudo tail -100 /var/log/asterisk/messages 2>/dev/null | grep -i "invite\|to:" | tail -5 | sed 's/^/   /' || warn "SIP сообщения не найдены"
echo ""

# Выключаем детальное логирование
sudo asterisk -rx "core set verbose 0" > /dev/null 2>&1
sudo asterisk -rx "core set debug 0" > /dev/null 2>&1
sudo asterisk -rx "pjsip set logger off" > /dev/null 2>&1
sudo asterisk -rx "rtp set debug off" > /dev/null 2>&1

info "Диагностика завершена!"

