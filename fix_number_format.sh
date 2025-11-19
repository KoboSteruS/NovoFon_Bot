#!/bin/bash
# Исправление формата номера для NovoFon

echo "=========================================="
echo "🔧 Исправление формата номера"
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
    error "Запустите с sudo: sudo bash fix_number_format.sh"
    exit 1
fi

CALLER_ID="+79675558164"

info "Исправляем dialplan для правильного формата номера NovoFon..."
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

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
    info "Старая секция удалена"
fi

# Добавляем правильную секцию outgoing
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
 ; Форматируем номер: убираем все нецифровые символы, добавляем +7 если начинается с 7 или 8
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
 same => n(dial),NoOp(Formatted number for NovoFon: ${OUTBOUND_NUM})
 same => n,NoOp(Calling via PJSIP/${OUTBOUND_NUM}@novofon)
 ; Используем форматированный номер с +
 same => n,Dial(PJSIP/${OUTBOUND_NUM}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: ${DIALSTATUS}, cause: ${HANGUPCAUSE})
 same => n,Hangup()

EOF

info "✅ Секция [outgoing] обновлена"

# Перезагружаем dialplan
info "Перезагружаем dialplan..."
asterisk -rx "dialplan reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке dialplan"
    exit 1
}

info "✅ Dialplan перезагружен"

# Проверяем конфигурацию
info "Проверяем конфигурацию..."
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "✅ Секция [outgoing] найдена"
    echo ""
    info "Содержимое секции [outgoing]:"
    sed -n '/^\[outgoing\]/,/^\[/p' /etc/asterisk/extensions.conf | head -25 | sed 's/^/   /'
else
    error "❌ Секция [outgoing] не найдена!"
    exit 1
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Изменения:"
info "1. Автоматическое форматирование номера:"
info "   - Убираются все нецифровые символы"
info "   - Если номер начинается с 7 → добавляется +"
info "   - Если номер начинается с 8 → конвертируется в +7..."
info "   - Если номер уже с +7 → используется как есть"
info "2. Увеличен timeout до 60 секунд"
info "3. Добавлено детальное логирование"

