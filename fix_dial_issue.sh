#!/bin/bash
# Исправление проблемы с Dial через NovoFon

echo "=========================================="
echo "🔧 Исправление проблемы с Dial"
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
    error "Запустите с sudo: sudo bash fix_dial_issue.sh"
    exit 1
fi

CALLER_ID="+79675558164"

info "Исправляем dialplan для правильного формата номера..."
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

# Удаляем старую секцию outgoing если есть
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

# Добавляем улучшенную секцию outgoing
info "Добавляем улучшенную секцию [outgoing]..."

cat >> /etc/asterisk/extensions.conf <<EOF

;=============== ИСХОДЯЩИЕ ЗВОНКИ ЧЕРЕЗ NOVOFON ===============

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Используется ботом через ARI: Local/{phone}@outgoing
exten => _X.,1,NoOp(=== Outgoing call to \${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=$CALLER_ID)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Original number: \${EXTEN})
 ; Форматируем номер для NovoFon: добавляем + если его нет
 same => n,Set(OUTBOUND_NUM=\${EXTEN})
 same => n,GotoIf(\$["\${OUTBOUND_NUM:0:1}" = "+"]?dial)
 same => n,Set(OUTBOUND_NUM=+\${OUTBOUND_NUM})
 same => n(dial),NoOp(Formatted number for NovoFon: \${OUTBOUND_NUM})
 same => n,NoOp(Calling via PJSIP/\${OUTBOUND_NUM}@novofon)
 ; Пробуем сначала с +, если не работает - без +
 same => n,Dial(PJSIP/\${OUTBOUND_NUM}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: \${DIALSTATUS}, cause: \${HANGUPCAUSE})
 ; Если не получилось с +, пробуем без +
 same => n,GotoIf(\$["\${DIALSTATUS}" = "NOANSWER"]?try_without_plus)
 same => n,GotoIf(\$["\${DIALSTATUS}" = "CHANUNAVAIL"]?try_without_plus)
 same => n,GotoIf(\$["\${DIALSTATUS}" = "CONGESTION"]?try_without_plus)
 same => n,Hangup()
 same => n(try_without_plus),NoOp(Trying without + prefix...)
 same => n,Set(OUTBOUND_NUM=\${EXTEN})
 same => n,NoOp(Calling via PJSIP/\${OUTBOUND_NUM}@novofon (no +))
 same => n,Dial(PJSIP/\${OUTBOUND_NUM}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: \${DIALSTATUS}, cause: \${HANGUPCAUSE})
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
    sed -n '/^\[outgoing\]/,/^\[/p' /etc/asterisk/extensions.conf | head -15 | sed 's/^/   /'
else
    error "❌ Секция [outgoing] не найдена!"
    exit 1
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Изменения:"
info "1. Добавлена автоматическая обработка формата номера (+ добавляется если его нет)"
info "2. Увеличен timeout до 60 секунд"
info "3. Добавлено логирование статуса Dial"

