#!/bin/bash
# Настройка Asterisk для IP-аутентификации NovoFon

set -e

echo "=========================================="
echo "📞 Настройка Asterisk (IP-аутентификация)"
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
    error "Запустите с sudo: sudo bash setup_ip_auth.sh"
    exit 1
fi

read -p "Твой номер (Caller ID, например +79581114585): " CALLER_ID
PUBLIC_IP="109.73.192.126"

info "Настраиваем Asterisk для IP-аутентификации..."

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

# Создаём pjsip.conf для IP-аутентификации
info "Создаём pjsip.conf (БЕЗ auth)..."

cat > /etc/asterisk/pjsip.conf <<EOF
;
; PJSIP Configuration для NovoFon (IP-аутентификация)
; БЕЗ логина/пароля - авторизация по IP
;

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060
external_media_address = $PUBLIC_IP
external_signaling_address = $PUBLIC_IP

;=============== NOVOFON TRUNK (IP Auth) ===============

[novofon]
type = endpoint
context = from-novofon
disallow = all
allow = ulaw
allow = alaw
aors = novofon
transport = transport-udp
direct_media = no
ice_support = yes
force_rport = yes
rewrite_contact = yes
from_user = $CALLER_ID
from_domain = sip.novofon.ru

[novofon]
type = aor
contact = sip:sip.novofon.ru:5060
qualify_frequency = 60

; ВАЖНО: Нет секции auth - используется IP-аутентификация

; Identify для входящих от NovoFon
; (IP адреса NovoFon - уточни у поддержки если не работает)
[novofon-identify]
type = identify
endpoint = novofon
; Разрешаем входящие от любых IP (NovoFon сам проверит твой IP)
; Если знаешь конкретные IP NovoFon - укажи их:
; match = 31.31.196.0/24
; match = 31.31.197.0/24

EOF

info "✅ pjsip.conf создан (IP-аутентификация)"

# Обновляем extensions.conf
if ! grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "Добавляем секцию outgoing..."
    cat >> /etc/asterisk/extensions.conf <<EOF

[outgoing]
; Реальный звонок через NovoFon на внешний номер
exten => _X.,1,NoOp(=== Outgoing call to \${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=$CALLER_ID)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,Dial(PJSIP/\${EXTEN}@novofon,30)
 same => n,Hangup()
EOF
fi

sed -i "s/YOUR_CALLER_ID_HERE/$CALLER_ID/g" /etc/asterisk/extensions.conf

# Перезагружаем
info "Перезагружаем Asterisk..."
systemctl restart asterisk
sleep 2

if systemctl is-active --quiet asterisk; then
    info "✅ Asterisk запущен"
else
    error "❌ Asterisk не запустился"
    exit 1
fi

asterisk -rx "pjsip reload" > /dev/null 2>&1
asterisk -rx "dialplan reload" > /dev/null 2>&1

# Проверка
info "Проверяем endpoint..."
sleep 2
if asterisk -rx "pjsip show endpoints" | grep -q "novofon"; then
    info "✅ Endpoint novofon найден"
    asterisk -rx "pjsip show endpoints" | grep -A 3 novofon
else
    warn "⚠️  Endpoint не найден"
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Теперь сделай тестовый звонок:"
info "  sudo asterisk -rvvv"
info "  channel originate Local/79991234567@outgoing application Playback hello-world"
echo ""

