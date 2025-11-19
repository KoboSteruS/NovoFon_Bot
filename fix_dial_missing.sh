#!/bin/bash
# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавление реального Dial() в dialplan

echo "=========================================="
echo "🔧 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавление Dial()"
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
    error "Запустите с sudo: sudo bash fix_dial_missing.sh"
    exit 1
fi

info "Проверяем текущую конфигурацию..."
echo ""

# 1. Проверяем extensions.conf
info "1. Проверяем extensions.conf на наличие Dial()..."
if grep -q "Dial(PJSIP" /etc/asterisk/extensions.conf; then
    warn "   Dial() найден, но проверим правильность..."
    grep "Dial(PJSIP" /etc/asterisk/extensions.conf | sed 's/^/   /'
else
    error "   ❌ Dial() НЕ НАЙДЕН! Это критическая ошибка!"
    info "   Исправляем..."
fi
echo ""

# 2. Проверяем pjsip.conf
info "2. Проверяем pjsip.conf на наличие endpoint novofon..."
if grep -q "^\[novofon\]" /etc/asterisk/pjsip.conf; then
    info "   ✅ Endpoint novofon найден"
    echo ""
    info "   Содержимое endpoint novofon:"
    sed -n '/^\[novofon\]/,/^\[/p' /etc/asterisk/pjsip.conf | head -20 | sed 's/^/   /'
else
    error "   ❌ Endpoint novofon НЕ НАЙДЕН!"
    info "   Нужно настроить PJSIP для NovoFon"
fi
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# 3. Исправляем extensions.conf - добавляем реальный Dial()
info "3. Исправляем extensions.conf - добавляем реальный Dial()..."

# Удаляем старую секцию outgoing
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "   Удаляем старую секцию [outgoing]..."
    python3 << 'PYEOF'
with open('/etc/asterisk/extensions.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
for line in lines:
    if line.strip().startswith('[outgoing]'):
        skip = True
        continue
    if skip and line.strip().startswith('[') and not line.strip().startswith('[outgoing]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/extensions.conf', 'w') as f:
    f.writelines(output)
PYEOF
    info "   ✅ Старая секция удалена"
fi

# Добавляем ПРАВИЛЬНУЮ секцию outgoing с реальным Dial()
info "   Добавляем правильную секцию [outgoing] с Dial()..."
cat >> /etc/asterisk/extensions.conf <<'EOF'

;=============== ИСХОДЯЩИЕ ЗВОНКИ ЧЕРЕЗ NOVOFON ===============

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Используется ботом через ARI: Local/{phone}@outgoing
exten => _X.,1,NoOp(=== Outgoing call to ${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=+79675558164)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Original number: ${EXTEN})
 ; Форматируем номер: убираем все нецифровые символы, добавляем +7 если начинается с 7
 same => n,Set(RAW_NUM=${EXTEN})
 same => n,Set(RAW_NUM=${RAW_NUM//[^0-9]/})
 same => n,NoOp(Cleaned number: ${RAW_NUM})
 ; Если номер начинается с 7, добавляем +
 same => n,GotoIf($["${RAW_NUM:0:1}" = "7"]?add_plus)
 same => n,GotoIf($["${RAW_NUM:0:1}" = "8"]?convert_8_to_7)
 same => n,GotoIf($["${RAW_NUM:0:2}" = "+7"]?already_plus)
 same => n,Set(OUTBOUND_NUM=+7${RAW_NUM})
 same => n,Goto(dial)
 same => n(add_plus),Set(OUTBOUND_NUM=+${RAW_NUM})
 same => n,Goto(dial)
 same => n(convert_8_to_7),Set(OUTBOUND_NUM=+7${RAW_NUM:1})
 same => n,Goto(dial)
 same => n(already_plus),Set(OUTBOUND_NUM=${RAW_NUM})
 ; ВАЖНО: РЕАЛЬНЫЙ Dial() - это то, что отправляет звонок на NovoFon!
 same => n(dial),NoOp(Formatted number for NovoFon: ${OUTBOUND_NUM})
 same => n,NoOp(Calling via PJSIP/${OUTBOUND_NUM}@novofon)
 same => n,Dial(PJSIP/${OUTBOUND_NUM}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: ${DIALSTATUS}, cause: ${HANGUPCAUSE})
 same => n,Hangup()

EOF

info "   ✅ Секция [outgoing] с Dial() добавлена"
echo ""

# 4. Проверяем pjsip.conf - если нет novofon, добавляем
if ! grep -q "^\[novofon\]" /etc/asterisk/pjsip.conf; then
    warn "4. Endpoint novofon не найден, добавляем..."
    
    # Проверяем, есть ли transport-udp
    if ! grep -q "^\[transport-udp\]" /etc/asterisk/pjsip.conf; then
        info "   Добавляем transport-udp..."
        cat >> /etc/asterisk/pjsip.conf <<'EOF'

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060

EOF
    fi
    
    # Добавляем endpoint novofon для IP-аутентификации
    info "   Добавляем endpoint novofon для IP-аутентификации..."
    cat >> /etc/asterisk/pjsip.conf <<'EOF'

;=============== NOVOFON SIP TRUNK (IP Authentication) ===============

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
from_user = +79675558164
from_domain = sip.novofon.ru
outbound_proxy = sip.novofon.ru:5060

[novofon]
type = aor
contact = sip:sip.novofon.ru:5060
qualify_frequency = 60
maximum_expiration = 3600

; ВАЖНО: Нет секции auth - используется IP-аутентификация

EOF
    info "   ✅ Endpoint novofon добавлен"
else
    info "4. ✅ Endpoint novofon уже существует"
    
    # Проверяем, есть ли outbound_proxy
    if ! grep -A 15 "^\[novofon\]" /etc/asterisk/pjsip.conf | grep -q "outbound_proxy"; then
        warn "   outbound_proxy не найден, добавляем..."
        # Добавляем outbound_proxy после from_domain
        sed -i '/from_domain = sip.novofon.ru/a outbound_proxy = sip.novofon.ru:5060' /etc/asterisk/pjsip.conf
        info "   ✅ outbound_proxy добавлен"
    fi
fi
echo ""

# 5. Перезагружаем конфигурацию
info "5. Перезагружаем конфигурацию..."
asterisk -rx "dialplan reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке dialplan"
    exit 1
}
asterisk -rx "pjsip reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке PJSIP"
    exit 1
}
info "✅ Конфигурация перезагружена"
echo ""

# 6. Проверяем результат
info "6. Проверяем результат..."
echo ""

info "   Dialplan [outgoing]:"
asterisk -rx "dialplan show outgoing" 2>/dev/null | grep -E "outgoing|Dial|PJSIP" | head -5 | sed 's/^/   /'
echo ""

info "   PJSIP endpoint novofon:"
asterisk -rx "pjsip show endpoint novofon" 2>/dev/null | head -10 | sed 's/^/   /'
echo ""

# 7. Проверяем, что Dial() действительно есть
if grep -q "Dial(PJSIP" /etc/asterisk/extensions.conf; then
    info "7. ✅ Dial() найден в extensions.conf:"
    grep "Dial(PJSIP" /etc/asterisk/extensions.conf | sed 's/^/   /'
else
    error "7. ❌ Dial() ВСЁ ЕЩЁ НЕ НАЙДЕН!"
    error "   Проверь файл вручную: /etc/asterisk/extensions.conf"
    exit 1
fi

echo ""
info "✅ Исправление завершено!"
echo ""
info "Теперь попробуй сделать тестовый звонок:"
info "   sudo asterisk -rx \"channel originate Local/79522675444@outgoing application Playback hello-world\""
info ""
info "Или через API бота:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate -H \"Content-Type: application/json\" -d '{\"phone\": \"+79522675444\"}'"

