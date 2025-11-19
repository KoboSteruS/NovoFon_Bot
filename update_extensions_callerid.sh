#!/bin/bash
# Обновление caller ID в extensions.conf

echo "=========================================="
echo "📞 Обновление Caller ID в extensions.conf"
echo "=========================================="
echo ""

# Цвета
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    echo "Запустите с sudo"
    exit 1
fi

CALLER_ID="+79675558164"

info "Обновляем CALLERID в extensions.conf на $CALLER_ID..."

# Обновляем CALLERID во всех секциях
sed -i "s/Set(CALLERID(num)=.*)/Set(CALLERID(num)=$CALLER_ID)/g" /etc/asterisk/extensions.conf

info "✅ Caller ID обновлён"

# Перезагружаем dialplan
asterisk -rx "dialplan reload" > /dev/null 2>&1
info "✅ Dialplan перезагружен"

