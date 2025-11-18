#!/bin/bash
# Исправление конфигурации Asterisk

set -e

echo "=========================================="
echo "🔧 Исправление конфигурации Asterisk"
echo "=========================================="
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервные копии созданы в $BACKUP_DIR"

# Исправляем pjsip.conf - убираем или комментируем identify
info "Исправляем pjsip.conf..."
if grep -q "^\[novofon-identify\]" /etc/asterisk/pjsip.conf; then
    # Комментируем секцию identify
    sudo sed -i '/^\[novofon-identify\]/,/^$/s/^/# /' /etc/asterisk/pjsip.conf
    info "✅ Секция novofon-identify закомментирована"
fi

# Исправляем extensions.conf - убираем дубликаты test-real-call
info "Исправляем extensions.conf..."
# Удаляем все секции test-real-call кроме первой
sudo awk '
/^\[test-real-call\]/ {
    if (seen++) next
}
{ print }
' /etc/asterisk/extensions.conf > /tmp/extensions.conf.tmp
sudo mv /tmp/extensions.conf.tmp /etc/asterisk/extensions.conf
info "✅ Дубликаты test-real-call удалены"

# Перезагружаем
info "Перезагружаем конфигурации..."
sudo asterisk -rx "pjsip reload" > /dev/null 2>&1
sudo asterisk -rx "dialplan reload" > /dev/null 2>&1

echo ""
info "✅ Конфигурация исправлена!"
echo ""
info "Теперь попробуй сделать звонок:"
info "  sudo asterisk -rvvv"
info "  channel originate Local/79991234567@test-real-call application Playback hello-world"
echo ""

