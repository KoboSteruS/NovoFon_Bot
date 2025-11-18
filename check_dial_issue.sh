#!/bin/bash
# Проверка проблемы с Dial через NovoFon

echo "=========================================="
echo "🔍 Проверка проблемы с Dial"
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

# 1. Проверяем логи Asterisk на ошибки Dial
info "1. Проверяем логи Asterisk на ошибки Dial/PJSIP..."
sudo tail -200 /var/log/asterisk/messages 2>/dev/null | grep -i "dial\|pjsip\|novofon\|79522675444" | tail -30 | sed 's/^/   /' || warn "Логи не найдены"
echo ""

# 2. Проверяем статус PJSIP endpoint
info "2. Проверяем статус PJSIP endpoint novofon..."
sudo asterisk -rx "pjsip show endpoints" | grep -A 10 "novofon" | sed 's/^/   /'
echo ""

# 3. Проверяем конфигурацию PJSIP
info "3. Проверяем конфигурацию PJSIP novofon..."
sudo grep -A 20 "^\[novofon\]" /etc/asterisk/pjsip.conf | head -25 | sed 's/^/   /'
echo ""

# 4. Проверяем dialplan outgoing
info "4. Проверяем dialplan outgoing..."
sudo asterisk -rx "dialplan show outgoing" | head -20 | sed 's/^/   /'
echo ""

# 5. Проверяем, может ли Asterisk сделать тестовый звонок
info "5. Проверяем, может ли Asterisk сделать тестовый звонок через CLI..."
info "   (Это займёт несколько секунд)"
echo ""

# Включаем verbose для детального логирования
sudo asterisk -rx "core set verbose 3" > /dev/null 2>&1
sudo asterisk -rx "core set debug 1" > /dev/null 2>&1

# Пробуем сделать тестовый звонок напрямую через Asterisk CLI
info "Пробуем сделать тестовый звонок через Asterisk CLI..."
echo "   Команда: channel originate Local/79522675444@outgoing application Playback hello-world"
echo ""

# Делаем звонок в фоне и смотрим логи
(sudo asterisk -rx "channel originate Local/79522675444@outgoing application Playback hello-world" &) 2>/dev/null
sleep 3

# Смотрим логи
info "Логи Asterisk после тестового звонка:"
sudo tail -50 /var/log/asterisk/messages 2>/dev/null | grep -i "dial\|pjsip\|novofon\|79522675444\|error\|fail" | tail -20 | sed 's/^/   /' || warn "Логи не найдены"
echo ""

# Выключаем verbose
sudo asterisk -rx "core set verbose 0" > /dev/null 2>&1
sudo asterisk -rx "core set debug 0" > /dev/null 2>&1

# 6. Проверяем формат номера
info "6. Проверяем формат номера..."
info "   Текущий формат в dialplan: \${EXTEN} (79522675444)"
info "   NovoFon может требовать формат: +7... или 7..."
echo ""

# 7. Проверяем, есть ли регистрация на NovoFon
info "7. Проверяем регистрацию на NovoFon..."
REGISTRATION=$(sudo asterisk -rx "pjsip show registrations" 2>/dev/null | grep -i "novofon")
if [ -n "$REGISTRATION" ]; then
    info "   Регистрация найдена:"
    echo "$REGISTRATION" | sed 's/^/   /'
else
    warn "   Регистрация на NovoFon не найдена"
    info "   Это нормально для IP-аутентификации"
fi
echo ""

info "Диагностика завершена!"

