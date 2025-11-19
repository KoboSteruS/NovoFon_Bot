#!/bin/bash
# Исправление проблемы с обрезанием номера в dialplan

echo "=========================================="
echo "🔧 Исправление обрезания номера в dialplan"
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
    error "Запустите с sudo: sudo bash fix_dialplan_number.sh"
    exit 1
fi

info "Проблема: номер обрезается до +7 вместо полного номера"
info "Исправляем dialplan..."
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# Удаляем старую секцию outgoing
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "Удаляем старую секцию [outgoing]..."
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
    info "✅ Старая секция удалена"
fi

# Добавляем ПРАВИЛЬНУЮ секцию outgoing
info "Добавляем правильную секцию [outgoing]..."
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
 same => n,NoOp(Cleaned number: ${RAW_NUM})
 ; Проверяем длину и форматируем правильно
 same => n,Set(NUM_LEN=${LEN(${RAW_NUM})})
 same => n,NoOp(Number length: ${NUM_LEN})
 ; Если номер начинается с 7 и длина 11 - добавляем +
 same => n,GotoIf($["${RAW_NUM:0:1}" = "7"]?check_len_11)
 same => n,GotoIf($["${RAW_NUM:0:1}" = "8"]?convert_8)
 same => n,GotoIf($["${RAW_NUM:0:2}" = "+7"]?already_plus)
 ; Если не начинается с 7 или 8 - добавляем +7
 same => n,Set(OUTBOUND_NUM=+7${RAW_NUM})
 same => n,Goto(dial)
 ; Проверяем длину для номеров начинающихся с 7
 same => n(check_len_11),GotoIf($["${NUM_LEN}" = "11"]?add_plus_to_7)
 same => n,GotoIf($["${NUM_LEN}" = "10"]?add_plus_to_7)
 same => n,Set(OUTBOUND_NUM=+${RAW_NUM})
 same => n,Goto(dial)
 same => n(add_plus_to_7),Set(OUTBOUND_NUM=+${RAW_NUM})
 same => n,Goto(dial)
 ; Конвертируем 8 в +7
 same => n(convert_8),Set(OUTBOUND_NUM=+7${RAW_NUM:1})
 same => n,Goto(dial)
 ; Уже с +7
 same => n(already_plus),Set(OUTBOUND_NUM=${RAW_NUM})
 ; ВАЖНО: Используем полный номер в Dial()
 same => n(dial),NoOp(Formatted number for NovoFon: ${OUTBOUND_NUM})
 same => n,NoOp(Full number length: ${LEN(${OUTBOUND_NUM})})
 same => n,NoOp(Calling via PJSIP/${OUTBOUND_NUM}@novofon-endpoint)
 ; Используем переменную OUTBOUND_NUM полностью
 same => n,Dial(PJSIP/${OUTBOUND_NUM}@novofon-endpoint,60,Tt)
 same => n,NoOp(Dial ended with status: ${DIALSTATUS}, cause: ${HANGUPCAUSE})
 same => n,Hangup()

EOF

info "✅ Секция [outgoing] обновлена"
echo ""

# Перезагружаем dialplan
info "Перезагружаем dialplan..."
asterisk -rx "dialplan reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке dialplan"
    exit 1
}
info "✅ Dialplan перезагружен"
echo ""

# Проверяем результат
info "Проверяем результат..."
if grep -q "Dial(PJSIP/\${OUTBOUND_NUM}" /etc/asterisk/extensions.conf; then
    info "✅ Dial() с переменной OUTBOUND_NUM найден"
    grep "Dial(PJSIP" /etc/asterisk/extensions.conf | sed 's/^/   /'
else
    error "❌ Dial() не найден!"
    exit 1
fi

echo ""
info "✅ Исправление завершено!"
info ""
info "Теперь номер не будет обрезаться до +7"

