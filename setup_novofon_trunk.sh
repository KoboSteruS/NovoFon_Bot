#!/bin/bash
# Скрипт для настройки Asterisk с данными от NovoFon

set -e

echo "=========================================="
echo "📞 Настройка Asterisk для NovoFon транка"
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
    error "Запустите с sudo: sudo bash setup_novofon_trunk.sh"
    exit 1
fi

echo "Введи данные из личного кабинета NovoFon:"
echo ""
read -p "SIP логин (username) транка 05224: " SIP_LOGIN
read -sp "SIP пароль транка 05224: " SIP_PASSWORD
echo ""
read -p "SIP сервер (обычно sip.novofon.ru:5060): " SIP_SERVER
read -p "Твой номер (Caller ID, например +79581114585): " CALLER_ID

# Значения по умолчанию
SIP_SERVER=${SIP_SERVER:-sip.novofon.ru:5060}
PUBLIC_IP="109.73.192.126"

info "Обновляем конфигурации..."

# Создаём резервную копию
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

# Обновляем pjsip.conf
info "Обновляем pjsip.conf..."

cat > /etc/asterisk/pjsip.conf <<EOF
;
; PJSIP Configuration для NovoFon SIP транка
;

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060
external_media_address = $PUBLIC_IP
external_signaling_address = $PUBLIC_IP

;=============== NOVOFON TRUNK ===============

[novofon]
type = endpoint
context = from-novofon
disallow = all
allow = ulaw
allow = alaw
aors = novofon
auth = novofon
direct_media = no
ice_support = yes
force_rport = yes
rewrite_contact = yes
from_user = $SIP_LOGIN
from_domain = sip.novofon.ru

[novofon]
type = aor
contact = sip:${SIP_SERVER%:*}

[novofon]
type = auth
auth_type = userpass
username = $SIP_LOGIN
password = $SIP_PASSWORD

EOF

info "✅ pjsip.conf обновлён"

# Обновляем extensions.conf (добавляем секцию outgoing если её нет)
if ! grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "Добавляем секцию outgoing в extensions.conf..."
    cat >> /etc/asterisk/extensions.conf <<EOF

[outgoing]
; Реальный звонок через NovoFon на внешний номер
exten => _X.,1,NoOp(=== Outgoing call to \${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=$CALLER_ID)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,Dial(PJSIP/\${EXTEN}@novofon,30)
 same => n,Hangup()
EOF
    info "✅ Секция outgoing добавлена"
fi

# Обновляем Caller ID в extensions.conf если есть placeholder
sed -i "s/YOUR_CALLER_ID_HERE/$CALLER_ID/g" /etc/asterisk/extensions.conf

# Перезагружаем конфигурации
info "Перезагружаем Asterisk..."
systemctl restart asterisk
sleep 2

# Проверяем статус
if systemctl is-active --quiet asterisk; then
    info "✅ Asterisk запущен"
else
    error "❌ Asterisk не запустился. Проверь логи: journalctl -u asterisk"
    exit 1
fi

# Перезагружаем модули
asterisk -rx "pjsip reload" > /dev/null 2>&1
asterisk -rx "dialplan reload" > /dev/null 2>&1

# Проверяем endpoint
info "Проверяем endpoint..."
sleep 2
if asterisk -rx "pjsip show endpoints" | grep -q "novofon"; then
    info "✅ Endpoint novofon найден"
else
    warn "⚠️  Endpoint novofon не найден. Проверь конфигурацию."
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Следующие шаги:"
info "1. Проверь endpoint: sudo asterisk -rx 'pjsip show endpoints'"
info "2. Сделай тестовый звонок:"
info "   sudo asterisk -rvvv"
info "   channel originate Local/79991234567@outgoing application Playback hello-world"
info "3. Проверь логи: sudo tail -f /var/log/asterisk/full"
echo ""

