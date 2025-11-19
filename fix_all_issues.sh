#!/bin/bash
# Комплексное исправление всех проблем

echo "=========================================="
echo "🔧 Комплексное исправление всех проблем"
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
    error "Запустите с sudo: sudo bash fix_all_issues.sh"
    exit 1
fi

info "Исправляем все проблемы разом..."
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# 1. Добавляем identify
info "1. Добавляем identify для NovoFon..."

# Удаляем старую секцию identify если есть
if grep -q "^\[novofon-identify\]" /etc/asterisk/pjsip.conf; then
    python3 << 'PYEOF'
with open('/etc/asterisk/pjsip.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
for line in lines:
    if line.strip().startswith('[novofon-identify]'):
        skip = True
        continue
    if skip and line.strip().startswith('[') and not line.strip().startswith('[novofon-identify]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.writelines(output)
PYEOF
fi

# Получаем IP адрес sip.novofon.ru
NOVOFON_IP=$(dig +short sip.novofon.ru 2>/dev/null | head -1 || echo "37.139.38.224")
NOVOFON_SUBNET=$(echo $NOVOFON_IP | cut -d'.' -f1-3)

# Добавляем identify
cat >> /etc/asterisk/pjsip.conf <<EOF

;=============== IDENTIFY ДЛЯ NOVOFON ===============

[novofon-identify]
type = identify
endpoint = novofon-endpoint
match = sip.novofon.ru
match = $NOVOFON_IP
match = $NOVOFON_SUBNET.0/24
match = 31.31.196.0/24
match = 31.31.197.0/24

EOF

info "   ✅ Identify добавлен"
echo ""

# 2. Исправляем dialplan - номер обрезается до +7
info "2. Исправляем dialplan - номер обрезается до +7..."

# Удаляем старую секцию outgoing
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
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
fi

# Добавляем ПРАВИЛЬНУЮ секцию outgoing
cat >> /etc/asterisk/extensions.conf <<'EOF'

;=============== ИСХОДЯЩИЕ ЗВОНКИ ЧЕРЕЗ NOVOFON ===============

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Используется ботом через ARI: Local/{phone}@outgoing
exten => _X.,1,NoOp(=== Outgoing call to ${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=+79675558164)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Original number: ${EXTEN})
 ; Форматируем номер: убираем все нецифровые символы
 same => n,Set(RAW_NUM=${EXTEN})
 same => n,Set(RAW_NUM=${RAW_NUM//[^0-9]/})
 same => n,NoOp(Cleaned number: ${RAW_NUM}, length: ${LEN(${RAW_NUM})})
 ; Если номер начинается с 7 и длина 11 - добавляем +
 same => n,GotoIf($["${RAW_NUM:0:1}" = "7"]?check_len)
 same => n,GotoIf($["${RAW_NUM:0:1}" = "8"]?convert_8)
 same => n,GotoIf($["${RAW_NUM:0:2}" = "+7"]?already_plus)
 ; Если не начинается с 7 или 8 - добавляем +7
 same => n,Set(OUTBOUND_NUM=+7${RAW_NUM})
 same => n,Goto(dial)
 ; Проверяем длину для номеров начинающихся с 7
 same => n(check_len),GotoIf($["${LEN(${RAW_NUM})}" = "11"]?add_plus_to_7)
 same => n,GotoIf($["${LEN(${RAW_NUM})}" = "10"]?add_plus_to_7)
 same => n,Set(OUTBOUND_NUM=+${RAW_NUM})
 same => n,Goto(dial)
 same => n(add_plus_to_7),Set(OUTBOUND_NUM=+${RAW_NUM})
 same => n,Goto(dial)
 ; Конвертируем 8 в +7
 same => n(convert_8),Set(OUTBOUND_NUM=+7${RAW_NUM:1})
 same => n,Goto(dial)
 ; Уже с +7
 same => n(already_plus),Set(OUTBOUND_NUM=${RAW_NUM})
 ; ВАЖНО: Используем полный номер в Dial() - используем переменную напрямую
 same => n(dial),NoOp(Formatted number for NovoFon: ${OUTBOUND_NUM})
 same => n,NoOp(Full number length: ${LEN(${OUTBOUND_NUM})})
 same => n,NoOp(Calling via PJSIP/${OUTBOUND_NUM}@novofon-endpoint)
 ; КРИТИЧНО: Используем переменную OUTBOUND_NUM полностью, не обрезаем
 same => n,Set(DIAL_TARGET=${OUTBOUND_NUM})
 same => n,NoOp(Dial target: ${DIAL_TARGET})
 same => n,Dial(PJSIP/${DIAL_TARGET}@novofon-endpoint,60,Tt)
 same => n,NoOp(Dial ended with status: ${DIALSTATUS}, cause: ${HANGUPCAUSE})
 same => n,Hangup()

EOF

info "   ✅ Dialplan исправлен"
echo ""

# 3. Перезагружаем конфигурацию
info "3. Перезагружаем конфигурацию..."
asterisk -rx "pjsip reload" > /dev/null 2>&1
sleep 3
asterisk -rx "dialplan reload" > /dev/null 2>&1
info "✅ Конфигурация перезагружена"
echo ""

# 4. Проверяем результат
info "4. Проверяем результат..."
echo ""

info "Identify секции:"
asterisk -rx "pjsip show identifies" 2>/dev/null | grep -A 3 "novofon" | sed 's/^/   /' || warn "Identify не найден"
echo ""

info "Статус endpoint novofon-endpoint:"
asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | head -10 | sed 's/^/   /'
echo ""

info "Dialplan [outgoing] - проверяем Dial():"
asterisk -rx "dialplan show outgoing" 2>/dev/null | grep -E "Dial|OUTBOUND_NUM|DIAL_TARGET" | head -3 | sed 's/^/   /'
echo ""

# Ждём для qualify
info "Ждём 5 секунд для qualify..."
sleep 5

info "Финальный статус endpoint:"
ENDPOINT_STATUS=$(asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | grep -E "Endpoint:|Contact:|Status:" | head -3)
echo "$ENDPOINT_STATUS" | sed 's/^/   /'

echo ""
info "✅ Все исправления применены!"
echo ""
info "Теперь попробуй сделать тестовый звонок:"
info "   sudo asterisk -rx \"channel originate Local/79522675444@outgoing application Playback hello-world\""
info ""
info "Или через API:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate -H \"Content-Type: application/json\" -d '{\"phone\": \"+79522675444\"}'"
info ""
info "Проверь SIP трафик:"
info "   sudo tcpdump -i any -n port 5060 -v | grep -E \"INVITE|sip.novofon|+79522675444\""

