#!/bin/bash
# Полная настройка SIP транка NovoFon с регистрацией

echo "=========================================="
echo "📞 Настройка SIP транка NovoFon с регистрацией"
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
    error "Запустите с sudo: sudo bash setup_novofon_sip_registration.sh"
    exit 1
fi

# SIP данные NovoFon
SIP_USERNAME="606147"
SIP_PASSWORD="gMLPTrc9h3"
SIP_SERVER="sip.novofon.ru"
SIP_PORT="5060"
EXTERNAL_IP="109.73.192.126"

info "Настраиваем SIP транк NovoFon с регистрацией..."
info "Логин: $SIP_USERNAME"
info "Сервер: $SIP_SERVER:$SIP_PORT"
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# 1. Удаляем все старые секции novofon
info "1. Удаляем старые секции novofon..."
python3 << 'PYEOF'
import re

with open('/etc/asterisk/pjsip.conf', 'r') as f:
    content = f.read()

# Удаляем все секции связанные с novofon
lines = content.split('\n')
output = []
skip = False

for line in lines:
    # Если начинается секция novofon
    if re.match(r'^\[novofon', line):
        skip = True
        continue
    
    # Если начинается другая секция и мы были в novofon
    if skip and re.match(r'^\[', line) and not re.match(r'^\[novofon', line):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.write('\n'.join(output))
PYEOF

info "   ✅ Старые секции удалены"
echo ""

# 2. Проверяем наличие transport-udp
info "2. Проверяем transport-udp..."
if ! grep -q "^\[transport-udp\]" /etc/asterisk/pjsip.conf; then
    warn "   Transport-udp не найден, добавляем..."
    cat >> /etc/asterisk/pjsip.conf <<EOF

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060
external_signaling_address = $EXTERNAL_IP
external_media_address = $EXTERNAL_IP

EOF
    info "   ✅ Transport-udp добавлен"
else
    # Обновляем external адреса если нужно
    if ! grep -A 5 "^\[transport-udp\]" /etc/asterisk/pjsip.conf | grep -q "external_signaling_address"; then
        sed -i "/^\[transport-udp\]/a external_signaling_address = $EXTERNAL_IP\nexternal_media_address = $EXTERNAL_IP" /etc/asterisk/pjsip.conf
        info "   ✅ External адреса добавлены"
    else
        sed -i "s/^external_signaling_address = .*/external_signaling_address = $EXTERNAL_IP/" /etc/asterisk/pjsip.conf
        sed -i "s/^external_media_address = .*/external_media_address = $EXTERNAL_IP/" /etc/asterisk/pjsip.conf
        info "   ✅ External адреса обновлены"
    fi
fi
echo ""

# 3. Добавляем правильные секции NovoFon
info "3. Добавляем секции NovoFon с регистрацией..."
cat >> /etc/asterisk/pjsip.conf <<EOF

;=============== NOVOFON SIP TRUNK (с регистрацией) ===============

; ==========================================
; AUTH (логин/пароль)
; ==========================================

[novofon-auth]
type = auth
auth_type = userpass
username = $SIP_USERNAME
password = $SIP_PASSWORD

; ==========================================
; AOR (куда регистрироваться)
; ==========================================

[novofon-aor]
type = aor
contact = sip:$SIP_SERVER:$SIP_PORT
qualify_frequency = 30
qualify_timeout = 3.0
maximum_expiration = 3600
remove_existing = yes

; ==========================================
; ENDPOINT (твой SIP-транк)
; ==========================================

[novofon-endpoint]
type = endpoint
context = from-novofon
disallow = all
allow = ulaw
allow = alaw
aors = novofon-aor
outbound_auth = novofon-auth
from_user = $SIP_USERNAME
from_domain = $SIP_SERVER
transport = transport-udp
force_rport = yes
rewrite_contact = yes
direct_media = no
ice_support = yes

; ==========================================
; REGISTRATION (важно!)
; ==========================================

[novofon-registration]
type = registration
outbound_auth = novofon-auth
server_uri = sip:$SIP_SERVER:$SIP_PORT
client_uri = sip:$SIP_USERNAME@$SIP_SERVER
contact_user = $SIP_USERNAME
retry_interval = 60
forbidden_retry_interval = 300
max_retries = 100
transport = transport-udp
expiration = 3600

; ==========================================
; IDENTIFY (для входящих звонков)
; ==========================================

[novofon-identify]
type = identify
endpoint = novofon-endpoint
match = $SIP_SERVER
match = 37.139.38.224
match = 37.139.38.0/24
match = 31.31.196.0/24
match = 31.31.197.0/24

EOF

info "   ✅ Все секции добавлены"
echo ""

# 4. Перезагружаем PJSIP
info "4. Перезагружаем PJSIP..."
asterisk -rx "pjsip reload" > /dev/null 2>&1
sleep 5
info "✅ PJSIP перезагружен"
echo ""

# 5. Проверяем регистрацию
info "5. Проверяем регистрацию..."
echo ""
REG_STATUS=$(asterisk -rx "pjsip show registrations" 2>/dev/null | grep -i "novofon")
if [ -n "$REG_STATUS" ]; then
    info "   Статус регистрации:"
    echo "$REG_STATUS" | sed 's/^/   /'
    if echo "$REG_STATUS" | grep -qi "Registered"; then
        info "   ✅ Регистрация успешна!"
    else
        warn "   ⚠️  Регистрация не прошла, ждём ещё 10 секунд..."
        sleep 10
        REG_STATUS2=$(asterisk -rx "pjsip show registrations" 2>/dev/null | grep -i "novofon")
        if echo "$REG_STATUS2" | grep -qi "Registered"; then
            info "   ✅ Регистрация успешна!"
        else
            warn "   ⚠️  Регистрация всё ещё не прошла"
            info "   Проверь логи: sudo tail -50 /var/log/asterisk/messages | grep -i register"
        fi
    fi
else
    warn "   ⚠️  Регистрация не найдена"
    info "   Проверь логи: sudo tail -50 /var/log/asterisk/messages | grep -i register"
fi
echo ""

# 6. Проверяем endpoint
info "6. Проверяем endpoint novofon-endpoint..."
ENDPOINT_STATUS=$(asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | head -15)
echo "$ENDPOINT_STATUS" | sed 's/^/   /'
echo ""

# 7. Проверяем identify
info "7. Проверяем identify..."
IDENTIFY_STATUS=$(asterisk -rx "pjsip show identifies" 2>/dev/null | grep -A 3 "novofon")
if [ -n "$IDENTIFY_STATUS" ]; then
    echo "$IDENTIFY_STATUS" | sed 's/^/   /'
    info "   ✅ Identify настроен"
else
    warn "   ⚠️  Identify не найден"
fi
echo ""

# 8. Инструкции для теста
info "8. Теперь можно протестировать:"
echo ""
info "   Проверка регистрации:"
info "   sudo asterisk -rx \"pjsip show registrations\""
echo ""
info "   Тест исходящего звонка:"
info "   sudo asterisk -rx \"channel originate Local/79522675444@outgoing application Playback hello-world\""
echo ""
info "   Или через API бота:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate -H \"Content-Type: application/json\" -d '{\"phone\": \"+79522675444\"}'"
echo ""
info "   Проверка SIP трафика:"
info "   sudo tcpdump -i any -n port 5060 -v | grep -E \"INVITE|REGISTER|sip.novofon\""
echo ""

info "✅ Настройка завершена!"
info ""
info "После регистрации исходящие звонки должны работать автоматически!"

