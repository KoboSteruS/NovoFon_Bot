#!/bin/bash
# Проверка и исправление NAT настроек в Asterisk

echo "=========================================="
echo "🌐 Проверка NAT настроек"
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
    error "Запустите с sudo: sudo bash check_nat_settings.sh"
    exit 1
fi

# Получаем внешний IP
info "Определяем внешний IP сервера..."
EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "")
if [ -z "$EXTERNAL_IP" ]; then
    warn "Не удалось определить внешний IP автоматически"
    read -p "Введи внешний IP сервера вручную: " EXTERNAL_IP
fi

if [ -z "$EXTERNAL_IP" ]; then
    error "Внешний IP не указан, пропускаем проверку NAT"
    exit 1
fi

info "Внешний IP: $EXTERNAL_IP"
echo ""

# Проверяем pjsip.conf
info "Проверяем NAT настройки в pjsip.conf..."

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/pjsip.conf "$BACKUP_DIR/pjsip.conf.bak" 2>/dev/null || true

# Проверяем transport-udp
if grep -q "^\[transport-udp\]" /etc/asterisk/pjsip.conf; then
    info "✅ Секция [transport-udp] найдена"
    
    # Проверяем external_media_address
    if grep -A 10 "^\[transport-udp\]" /etc/asterisk/pjsip.conf | grep -q "external_media_address"; then
        CURRENT_MEDIA=$(grep -A 10 "^\[transport-udp\]" /etc/asterisk/pjsip.conf | grep "external_media_address" | awk -F'=' '{print $2}' | tr -d ' ')
        info "   external_media_address: $CURRENT_MEDIA"
        if [ "$CURRENT_MEDIA" != "$EXTERNAL_IP" ]; then
            warn "   ⚠️  external_media_address не совпадает с внешним IP"
            read -p "Обновить external_media_address на $EXTERNAL_IP? (y/n): " UPDATE_MEDIA
            if [ "$UPDATE_MEDIA" = "y" ] || [ "$UPDATE_MEDIA" = "Y" ]; then
                sed -i "s/^external_media_address = .*/external_media_address = $EXTERNAL_IP/" /etc/asterisk/pjsip.conf
                info "   ✅ Обновлено"
            fi
        else
            info "   ✅ external_media_address правильный"
        fi
    else
        warn "   ⚠️  external_media_address не найден"
        read -p "Добавить external_media_address = $EXTERNAL_IP? (y/n): " ADD_MEDIA
        if [ "$ADD_MEDIA" = "y" ] || [ "$ADD_MEDIA" = "Y" ]; then
            sed -i "/^\[transport-udp\]/,/^\[/ { /^external_signaling_address/a external_media_address = $EXTERNAL_IP\n" /etc/asterisk/pjsip.conf || \
            sed -i "/^\[transport-udp\]/a external_media_address = $EXTERNAL_IP" /etc/asterisk/pjsip.conf
            info "   ✅ Добавлено"
        fi
    fi
    
    # Проверяем external_signaling_address
    if grep -A 10 "^\[transport-udp\]" /etc/asterisk/pjsip.conf | grep -q "external_signaling_address"; then
        CURRENT_SIGNALING=$(grep -A 10 "^\[transport-udp\]" /etc/asterisk/pjsip.conf | grep "external_signaling_address" | awk -F'=' '{print $2}' | tr -d ' ')
        info "   external_signaling_address: $CURRENT_SIGNALING"
        if [ "$CURRENT_SIGNALING" != "$EXTERNAL_IP" ]; then
            warn "   ⚠️  external_signaling_address не совпадает с внешним IP"
            read -p "Обновить external_signaling_address на $EXTERNAL_IP? (y/n): " UPDATE_SIGNALING
            if [ "$UPDATE_SIGNALING" = "y" ] || [ "$UPDATE_SIGNALING" = "Y" ]; then
                sed -i "s/^external_signaling_address = .*/external_signaling_address = $EXTERNAL_IP/" /etc/asterisk/pjsip.conf
                info "   ✅ Обновлено"
            fi
        else
            info "   ✅ external_signaling_address правильный"
        fi
    else
        warn "   ⚠️  external_signaling_address не найден"
        read -p "Добавить external_signaling_address = $EXTERNAL_IP? (y/n): " ADD_SIGNALING
        if [ "$ADD_SIGNALING" = "y" ] || [ "$ADD_SIGNALING" = "Y" ]; then
            sed -i "/^\[transport-udp\]/a external_signaling_address = $EXTERNAL_IP" /etc/asterisk/pjsip.conf
            info "   ✅ Добавлено"
        fi
    fi
else
    error "❌ Секция [transport-udp] не найдена!"
    exit 1
fi

echo ""

# Перезагружаем PJSIP
if [ "$UPDATE_MEDIA" = "y" ] || [ "$UPDATE_MEDIA" = "Y" ] || [ "$UPDATE_SIGNALING" = "y" ] || [ "$UPDATE_SIGNALING" = "Y" ] || [ "$ADD_MEDIA" = "y" ] || [ "$ADD_MEDIA" = "Y" ] || [ "$ADD_SIGNALING" = "y" ] || [ "$ADD_SIGNALING" = "Y" ]; then
    info "Перезагружаем PJSIP..."
    asterisk -rx "pjsip reload" > /dev/null 2>&1
    sleep 2
    info "✅ PJSIP перезагружен"
fi

echo ""
info "✅ Проверка NAT настроек завершена!"

