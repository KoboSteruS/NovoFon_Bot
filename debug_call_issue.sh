#!/bin/bash
# Скрипт для диагностики проблем со звонками

echo "=========================================="
echo "🔍 Диагностика проблем со звонками"
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

# 1. Проверка статуса Asterisk
info "1. Статус Asterisk:"
sudo systemctl status asterisk --no-pager -l | head -20
echo ""

# 2. Проверка PJSIP endpoints
info "2. PJSIP endpoints:"
sudo asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -A 5 "novofon" || warn "NovoFon endpoint не найден"
echo ""

# 3. Проверка ARI приложений
info "3. ARI приложения:"
sudo asterisk -rx "ari show apps" 2>/dev/null || warn "ARI не настроен"
echo ""

# 4. Проверка последних логов Asterisk
info "4. Последние логи Asterisk (SIP):"
sudo tail -50 /var/log/asterisk/full 2>/dev/null | grep -i "sip\|novofon\|pjsip" | tail -20 || warn "Логи не найдены"
echo ""

# 5. Проверка последних ошибок
info "5. Последние ошибки Asterisk:"
sudo tail -50 /var/log/asterisk/full 2>/dev/null | grep -i "error\|warn\|fail" | tail -10 || warn "Ошибок не найдено"
echo ""

# 6. Проверка конфигурации PJSIP
info "6. Конфигурация NovoFon в pjsip.conf:"
sudo grep -A 20 "\[novofon\]" /etc/asterisk/pjsip.conf 2>/dev/null | head -30 || error "Конфигурация не найдена"
echo ""

# 7. Проверка dialplan для исходящих
info "7. Dialplan для исходящих звонков:"
sudo grep -A 10 "\[outgoing\]" /etc/asterisk/extensions.conf 2>/dev/null || warn "Dialplan [outgoing] не найден"
echo ""

# 8. Проверка активных каналов
info "8. Активные каналы:"
sudo asterisk -rx "core show channels" 2>/dev/null | head -10
echo ""

# 9. Проверка подключения к ARI
info "9. Проверка ARI подключения:"
curl -s -u novofon_bot:62015326495 http://localhost:8088/ari/asterisk/info | python3 -m json.tool 2>/dev/null | head -20 || error "ARI не доступен"
echo ""

# 10. Проверка логов бота
info "10. Последние логи бота (ARI/Asterisk):"
sudo journalctl -u novofon-bot -n 50 --no-pager | grep -i "ari\|asterisk\|call\|initiate" | tail -20
echo ""

info "Диагностика завершена!"
