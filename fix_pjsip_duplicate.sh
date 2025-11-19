#!/bin/bash
# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Дублирующиеся секции [novofon] в pjsip.conf

echo "=========================================="
echo "🔧 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Дубликаты в pjsip.conf"
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
    error "Запустите с sudo: sudo bash fix_pjsip_duplicate.sh"
    exit 1
fi

info "Проблема: две секции [novofon] в pjsip.conf перезаписывают друг друга!"
info "Исправляем: разделяем на [novofon-endpoint] и [novofon-aor]"
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# 1. Исправляем pjsip.conf
info "1. Исправляем pjsip.conf..."

# Создаём новый pjsip.conf без дубликатов
python3 << 'PYEOF'
import re

# Читаем текущий файл
with open('/etc/asterisk/pjsip.conf', 'r') as f:
    content = f.read()

# Удаляем все секции [novofon]
# Находим все секции novofon и удаляем их
lines = content.split('\n')
output = []
skip = False
in_novofon = False

for i, line in enumerate(lines):
    # Если начинается секция novofon
    if line.strip().startswith('[novofon]'):
        in_novofon = True
        skip = True
        continue
    
    # Если начинается другая секция и мы были в novofon
    if skip and line.strip().startswith('[') and not line.strip().startswith('[novofon]'):
        skip = False
        in_novofon = False
        output.append(line)
    elif not skip:
        output.append(line)

# Записываем обратно
with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.write('\n'.join(output))

print("Старые секции [novofon] удалены")
PYEOF

info "   ✅ Старые секции [novofon] удалены"

# Добавляем правильные секции в конец файла
info "   Добавляем правильные секции..."
cat >> /etc/asterisk/pjsip.conf <<'EOF'

;=============== NOVOFON SIP TRUNK (IP Authentication) ===============

[novofon-endpoint]
type = endpoint
context = from-novofon
disallow = all
allow = ulaw
allow = alaw
aors = novofon-aor
transport = transport-udp
direct_media = no
ice_support = yes
force_rport = yes
rewrite_contact = yes
from_user = +79675558164
from_domain = sip.novofon.ru
outbound_proxy = sip.novofon.ru:5060

[novofon-aor]
type = aor
contact = sip:sip.novofon.ru:5060
qualify_frequency = 60
maximum_expiration = 3600

; ВАЖНО: Нет секции auth - используется IP-аутентификация

EOF

info "   ✅ Правильные секции добавлены"
echo ""

# 2. Исправляем extensions.conf - обновляем Dial() на новое имя endpoint
info "2. Исправляем extensions.conf - обновляем Dial() на novofon-endpoint..."

# Заменяем все упоминания @novofon на @novofon-endpoint
sed -i 's/@novofon/@novofon-endpoint/g' /etc/asterisk/extensions.conf

# Удаляем дубликат [test-real-call]
if [ $(grep -c "^\[test-real-call\]" /etc/asterisk/extensions.conf) -gt 1 ]; then
    warn "   Найден дубликат [test-real-call], удаляем..."
    python3 << 'PYEOF'
with open('/etc/asterisk/extensions.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
found_first = False

for line in lines:
    if line.strip().startswith('[test-real-call]'):
        if not found_first:
            found_first = True
            output.append(line)
            skip = False
        else:
            skip = True
            continue
    elif skip and line.strip().startswith('[') and not line.strip().startswith('[test-real-call]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/extensions.conf', 'w') as f:
    f.writelines(output)
PYEOF
    info "   ✅ Дубликат удалён"
fi

info "   ✅ extensions.conf обновлён"
echo ""

# 3. Перезагружаем конфигурацию
info "3. Перезагружаем конфигурацию..."
asterisk -rx "pjsip reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке PJSIP"
    exit 1
}
sleep 2
asterisk -rx "dialplan reload" > /dev/null 2>&1 || {
    error "Ошибка при перезагрузке dialplan"
    exit 1
}
info "✅ Конфигурация перезагружена"
echo ""

# 4. Проверяем результат
info "4. Проверяем результат..."
echo ""

info "   PJSIP endpoints:"
asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -E "novofon|Endpoint:" | head -5 | sed 's/^/   /'
echo ""

info "   Детали endpoint novofon-endpoint:"
asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | head -15 | sed 's/^/   /'
echo ""

info "   Dialplan [outgoing] - проверяем Dial():"
asterisk -rx "dialplan show outgoing" 2>/dev/null | grep -E "Dial|PJSIP|novofon" | head -3 | sed 's/^/   /'
echo ""

# 5. Проверяем, что endpoint действительно существует
if asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | grep -q "novofon-endpoint"; then
    info "5. ✅ Endpoint novofon-endpoint найден и работает!"
else
    error "5. ❌ Endpoint novofon-endpoint НЕ НАЙДЕН!"
    error "   Проверь конфигурацию вручную"
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
info ""
info "Проверь SIP трафик:"
info "   sudo tcpdump -i any -n port 5060 -v | grep -E \"INVITE|200|sip.novofon\""

