#!/bin/bash
# Исправление qualify настроек для endpoint

echo "=========================================="
echo "🔧 Исправление qualify настроек"
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
    error "Запустите с sudo: sudo bash fix_endpoint_qualify.sh"
    exit 1
fi

info "Проблема: endpoint novofon-endpoint показывает NonQual"
info "Исправляем qualify настройки..."
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# Обновляем AOR с правильными qualify настройками
info "Обновляем AOR novofon-aor..."

# Удаляем старый AOR
if grep -q "^\[novofon-aor\]" /etc/asterisk/pjsip.conf; then
    python3 << 'PYEOF'
with open('/etc/asterisk/pjsip.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
for line in lines:
    if line.strip().startswith('[novofon-aor]'):
        skip = True
        continue
    if skip and line.strip().startswith('[') and not line.strip().startswith('[novofon-aor]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/pjsip.conf', 'w') as f:
    f.writelines(output)
PYEOF
    info "✅ Старый AOR удалён"
fi

# Добавляем правильный AOR
info "Добавляем правильный AOR с qualify..."
cat >> /etc/asterisk/pjsip.conf <<'EOF'

[novofon-aor]
type = aor
contact = sip:sip.novofon.ru:5060
qualify_frequency = 30
qualify_timeout = 3.0
maximum_expiration = 3600
remove_existing = yes

EOF

info "✅ AOR обновлён"
echo ""

# Перезагружаем PJSIP
info "Перезагружаем PJSIP..."
asterisk -rx "pjsip reload" > /dev/null 2>&1
sleep 5
info "✅ PJSIP перезагружен"
echo ""

# Проверяем результат
info "Проверяем результат..."
echo ""
info "Статус endpoint novofon-endpoint:"
asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | head -15 | sed 's/^/   /'
echo ""

info "Статус AOR novofon-aor:"
asterisk -rx "pjsip show aor novofon-aor" 2>/dev/null | head -10 | sed 's/^/   /'
echo ""

# Ждём немного для qualify
info "Ждём 5 секунд для qualify..."
sleep 5

info "Проверяем статус после qualify:"
asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | grep -E "Endpoint:|Contact:|Status:" | head -5 | sed 's/^/   /'

echo ""
info "✅ Исправление завершено!"

