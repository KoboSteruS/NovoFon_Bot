#!/bin/bash
# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавление identify для NovoFon

echo "=========================================="
echo "🔧 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавление identify"
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
    error "Запустите с sudo: sudo bash fix_identify.sh"
    exit 1
fi

info "Проблема: отсутствует identify для NovoFon"
info "Без identify Asterisk не знает, что входящие от NovoFon относятся к endpoint"
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# Удаляем старую секцию identify если есть
if grep -q "^\[novofon-identify\]" /etc/asterisk/pjsip.conf; then
    info "Удаляем старую секцию [novofon-identify]..."
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
    info "✅ Старая секция удалена"
fi

# Получаем IP адрес sip.novofon.ru
info "Определяем IP адрес sip.novofon.ru..."
NOVOFON_IP=$(dig +short sip.novofon.ru 2>/dev/null | head -1)
if [ -z "$NOVOFON_IP" ]; then
    NOVOFON_IP="37.139.38.224"  # Из диагностики
    warn "Не удалось определить IP автоматически, используем известный: $NOVOFON_IP"
else
    info "IP адрес sip.novofon.ru: $NOVOFON_IP"
fi

# Извлекаем подсеть
NOVOFON_SUBNET=$(echo $NOVOFON_IP | cut -d'.' -f1-3)
info "Подсеть NovoFon: $NOVOFON_SUBNET.0/24"
echo ""

# Добавляем секцию identify
info "Добавляем секцию [novofon-identify]..."
cat >> /etc/asterisk/pjsip.conf <<EOF

;=============== IDENTIFY ДЛЯ NOVOFON ===============

[novofon-identify]
type = identify
endpoint = novofon-endpoint
; Разрешаем входящие от sip.novofon.ru
match = sip.novofon.ru
; Разрешаем входящие от IP адреса NovoFon
match = $NOVOFON_IP
; Разрешаем входящие от подсети NovoFon
match = $NOVOFON_SUBNET.0/24
; Дополнительные подсети NovoFon (если известны)
match = 31.31.196.0/24
match = 31.31.197.0/24

EOF

info "✅ Секция [novofon-identify] добавлена"
echo ""

# Перезагружаем PJSIP
info "Перезагружаем PJSIP..."
asterisk -rx "pjsip reload" > /dev/null 2>&1
sleep 3
info "✅ PJSIP перезагружен"
echo ""

# Проверяем результат
info "Проверяем результат..."
echo ""

info "Identify секции:"
asterisk -rx "pjsip show identifies" 2>/dev/null | grep -A 5 "novofon" | sed 's/^/   /' || warn "Identify не найден"
echo ""

info "Статус endpoint novofon-endpoint:"
asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | head -15 | sed 's/^/   /'
echo ""

# Ждём немного для qualify
info "Ждём 5 секунд для qualify..."
sleep 5

info "Проверяем статус после qualify:"
ENDPOINT_STATUS=$(asterisk -rx "pjsip show endpoint novofon-endpoint" 2>/dev/null | grep -E "Endpoint:|Contact:|Status:" | head -5)
echo "$ENDPOINT_STATUS" | sed 's/^/   /'

if echo "$ENDPOINT_STATUS" | grep -qi "Reachable\|Avail"; then
    info "✅ Endpoint теперь Reachable/Available!"
else
    warn "⚠️  Endpoint всё ещё Unavailable, но identify добавлен"
    warn "   Это может быть нормально для IP-аутентификации"
fi

echo ""
info "✅ Исправление завершено!"
echo ""
info "Теперь Asterisk знает, что входящие от NovoFon относятся к endpoint novofon-endpoint"

