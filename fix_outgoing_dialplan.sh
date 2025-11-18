#!/bin/bash
# Скрипт для настройки dialplan для исходящих звонков

set -e

echo "=========================================="
echo "📞 Настройка dialplan для исходящих звонков"
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
    error "Запустите с sudo: sudo bash fix_outgoing_dialplan.sh"
    exit 1
fi

# Получаем Caller ID из .env или запрашиваем
CALLER_ID="+79675558164"  # Из your_env_config.txt

info "Используем Caller ID: $CALLER_ID"
info "Настраиваем dialplan..."

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"

# Проверяем, есть ли секция [outgoing]
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "Секция [outgoing] найдена, обновляем..."
    
    # Удаляем старую секцию outgoing (от [outgoing] до следующей секции [ или до конца файла)
    python3 << 'PYEOF'
import re

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
    
    info "Старая секция [outgoing] удалена"
fi

# Добавляем правильную секцию outgoing
info "Добавляем секцию [outgoing]..."

cat >> /etc/asterisk/extensions.conf <<EOF

;=============== ИСХОДЯЩИЕ ЗВОНКИ ЧЕРЕЗ NOVOFON ===============

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Используется ботом через ARI: Local/{phone}@outgoing
exten => _X.,1,NoOp(=== Outgoing call to \${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=$CALLER_ID)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Calling \${EXTEN} via PJSIP/novofon, timeout 60s)
 same => n,Dial(PJSIP/\${EXTEN}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: \${DIALSTATUS})
 same => n,Hangup()

EOF

info "✅ Секция [outgoing] добавлена/обновлена"

# Перезагружаем dialplan
info "Перезагружаем dialplan..."
asterisk -rx "dialplan reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке dialplan"
    exit 1
}

info "✅ Dialplan перезагружен"

# Проверяем, что секция добавлена
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "✅ Секция [outgoing] найдена в конфигурации"
    echo ""
    info "Содержимое секции [outgoing]:"
    sed -n '/^\[outgoing\]/,/^\[/p' /etc/asterisk/extensions.conf | head -10
else
    error "❌ Секция [outgoing] не найдена!"
    exit 1
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Теперь бот будет использовать: Local/{phone}@outgoing"
info "Dialplan будет делать: Dial(PJSIP/\${EXTEN}@novofon)"

