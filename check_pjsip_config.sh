#!/bin/bash
# Проверка и исправление конфигурации PJSIP

echo "=========================================="
echo "🔍 Проверка конфигурации PJSIP"
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

# 1. Проверяем текущую конфигурацию
info "1. Текущая конфигурация PJSIP novofon:"
sudo grep -A 30 "^\[novofon\]" /etc/asterisk/pjsip.conf | head -35 | sed 's/^/   /'
echo ""

# 2. Проверяем, что указано в from_user
FROM_USER=$(sudo grep -A 10 "^\[novofon\]" /etc/asterisk/pjsip.conf | grep "from_user" | awk -F'=' '{print $2}' | tr -d ' ')
if [ -n "$FROM_USER" ]; then
    info "2. from_user: $FROM_USER"
    if [[ "$FROM_USER" == +* ]]; then
        warn "   ⚠️  from_user содержит номер телефона (+...)"
        warn "   Для исходящих звонков обычно нужен SIP логин, а не номер"
        echo ""
        read -p "Есть ли у тебя SIP логин от NovoFon? (y/n): " HAS_LOGIN
        if [ "$HAS_LOGIN" = "y" ] || [ "$HAS_LOGIN" = "Y" ]; then
            read -p "Введи SIP логин: " SIP_LOGIN
            info "Обновляем from_user на $SIP_LOGIN..."
            sudo sed -i "s/^from_user = .*/from_user = $SIP_LOGIN/" /etc/asterisk/pjsip.conf
            info "✅ Обновлено"
            asterisk -rx "pjsip reload" > /dev/null 2>&1
            sleep 2
        fi
    else
        info "   ✅ from_user выглядит как SIP логин"
    fi
else
    warn "   ⚠️  from_user не найден"
fi
echo ""

# 3. Проверяем AOR contact
CONTACT=$(sudo grep -A 5 "type = aor" /etc/asterisk/pjsip.conf | grep "contact" | awk -F'=' '{print $2}' | tr -d ' ')
if [ -n "$CONTACT" ]; then
    info "3. AOR contact: $CONTACT"
    if [[ "$CONTACT" == *:5060* ]]; then
        info "   ✅ Порт указан"
    else
        warn "   ⚠️  Порт не указан, добавляем :5060"
        sudo sed -i "s|^contact = sip:sip.novofon.ru|contact = sip:sip.novofon.ru:5060|" /etc/asterisk/pjsip.conf
        asterisk -rx "pjsip reload" > /dev/null 2>&1
        sleep 2
    fi
else
    warn "   ⚠️  contact не найден"
fi
echo ""

# 4. Проверяем наличие auth секции
if sudo grep -q "type = auth" /etc/asterisk/pjsip.conf; then
    info "4. ✅ Секция auth найдена"
    AUTH_USER=$(sudo grep -A 3 "type = auth" /etc/asterisk/pjsip.conf | grep "username" | awk -F'=' '{print $2}' | tr -d ' ' | head -1)
    if [ -n "$AUTH_USER" ]; then
        info "   Username в auth: $AUTH_USER"
    fi
else
    warn "4. ⚠️  Секция auth не найдена"
    info "   Для IP-аутентификации это нормально"
fi
echo ""

# 5. Проверяем endpoint в реальном времени
info "5. Статус endpoint novofon:"
sudo asterisk -rx "pjsip show endpoint novofon" 2>/dev/null | head -20 | sed 's/^/   /'
echo ""

# 6. Проверяем, может ли Asterisk разрешить номер
info "6. Тест разрешения номера:"
sudo asterisk -rx "pjsip show endpoint +79522675444@novofon" 2>/dev/null | head -10 | sed 's/^/   /' || warn "   Не удалось разрешить +79522675444@novofon"
echo ""

info "Диагностика завершена!"


