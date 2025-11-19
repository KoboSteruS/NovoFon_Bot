#!/bin/bash
# Настройка регистрации на NovoFon для исходящих звонков

echo "=========================================="
echo "📞 Настройка регистрации на NovoFon"
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
    error "Запустите с sudo: sudo bash setup_novofon_registration.sh"
    exit 1
fi

info "Для исходящих звонков через NovoFon может потребоваться регистрация."
info "Даже при IP-аутентификации регистрация помогает установить соединение."
echo ""

read -p "Есть ли у тебя SIP логин и пароль от NovoFon? (y/n): " HAS_CREDENTIALS

if [ "$HAS_CREDENTIALS" != "y" ] && [ "$HAS_CREDENTIALS" != "Y" ]; then
    warn "Без SIP логина/пароля регистрация невозможна."
    info "Попробуем без регистрации, но это может не работать."
    exit 0
fi

echo ""
read -p "SIP логин (username): " SIP_LOGIN
read -sp "SIP пароль: " SIP_PASSWORD
echo ""
read -p "SIP сервер (обычно sip.novofon.ru): " SIP_SERVER
SIP_SERVER=${SIP_SERVER:-sip.novofon.ru}

CALLER_ID="+79675558164"
PUBLIC_IP="109.73.192.126"

info "Настраиваем регистрацию..."

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

# Читаем текущий pjsip.conf и добавляем регистрацию
if grep -q "^\[novofon-reg\]" /etc/asterisk/pjsip.conf; then
    info "Секция регистрации уже существует, обновляем..."
    # Удаляем старую секцию
    python3 << 'PYEOF'
with open('/etc/asterisk/pjsip.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
for line in lines:
    if line.strip().startswith('[novofon-reg]'):
        skip = True
        continue
    if skip and line.strip().startswith('[') and not line.strip().startswith('[novofon-reg]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.writelines(output)
PYEOF
fi

# Добавляем auth секцию если её нет
if ! grep -q "^\[novofon\]" /etc/asterisk/pjsip.conf | grep -q "type = auth"; then
    info "Добавляем секцию auth..."
    # Находим место после AOR и добавляем auth
    python3 << PYEOF
with open('/etc/asterisk/pjsip.conf', 'r') as f:
    lines = f.readlines()

output = []
found_aor = False
for i, line in enumerate(lines):
    output.append(line)
    if line.strip().startswith('[novofon]') and 'type = aor' in lines[i+1] if i+1 < len(lines) else False:
        found_aor = True
    if found_aor and line.strip() == '' and i+1 < len(lines) and not lines[i+1].strip().startswith('['):
        # Добавляем auth после AOR
        output.append('\n[novofon]\n')
        output.append('type = auth\n')
        output.append('auth_type = userpass\n')
        output.append(f'username = {SIP_LOGIN}\n')
        output.append(f'password = {SIP_PASSWORD}\n')
        found_aor = False

with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.writelines(output)
PYEOF
fi

# Добавляем регистрацию в конец файла
info "Добавляем секцию регистрации..."
cat >> /etc/asterisk/pjsip.conf <<EOF

;=============== РЕГИСТРАЦИЯ НА NOVOFON ===============

[novofon-reg]
type = registration
transport = transport-udp
outbound_auth = novofon
server_uri = sip:$SIP_SERVER:5060
client_uri = sip:$SIP_LOGIN@$SIP_SERVER
contact_user = $SIP_LOGIN
retry_interval = 60
forbidden_retry_interval = 300
expiration = 3600
max_retries = 10

EOF

# Обновляем endpoint чтобы использовать auth
if ! grep -q "auth = novofon" /etc/asterisk/pjsip.conf | grep -A 5 "\[novofon\]" | grep -q "type = endpoint"; then
    info "Обновляем endpoint для использования auth..."
    sed -i '/^\[novofon\]/,/^\[/ { /type = endpoint/,/^\[/ s/^\([^#]*\)$/\1/; /type = endpoint/,/^\[/ { /^auth =/! { /type = endpoint/a\
auth = novofon
; } } }' /etc/asterisk/pjsip.conf
fi

info "✅ Регистрация настроена"

# Перезагружаем PJSIP
info "Перезагружаем PJSIP..."
asterisk -rx "pjsip reload" > /dev/null 2>&1
sleep 3

# Проверяем регистрацию
info "Проверяем регистрацию..."
REG_STATUS=$(asterisk -rx "pjsip show registrations" 2>/dev/null | grep -i "novofon")
if [ -n "$REG_STATUS" ]; then
    info "✅ Регистрация найдена:"
    echo "$REG_STATUS" | sed 's/^/   /'
else
    warn "⚠️  Регистрация не найдена. Проверь логи:"
    info "   sudo asterisk -rx 'pjsip show registrations'"
    info "   sudo tail -50 /var/log/asterisk/messages | grep -i register"
fi

echo ""
info "✅ Настройка завершена!"


