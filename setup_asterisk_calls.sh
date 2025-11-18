#!/bin/bash
# Скрипт для настройки Asterisk для входящих/исходящих звонков

set -e

echo "=========================================="
echo "📞 Настройка Asterisk для звонков"
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
    error "Запустите с sudo: sudo bash setup_asterisk_calls.sh"
    exit 1
fi

# Запрашиваем данные
echo "Введите данные для настройки Asterisk:"
echo ""

read -p "SIP логин от NovoFon: " SIP_LOGIN
read -sp "SIP пароль от NovoFon: " SIP_PASSWORD
echo ""
read -p "Твой номер (Caller ID, например +79581114585): " CALLER_ID
read -p "Публичный IP сервера (или нажми Enter для автоопределения): " PUBLIC_IP

# Автоопределение IP если не указан
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_PUBLIC_IP_HERE")
    info "Определён публичный IP: $PUBLIC_IP"
fi

# Проверяем наличие конфигов
PJSIP_CONF="/etc/asterisk/pjsip.conf"
EXTENSIONS_CONF="/etc/asterisk/extensions.conf"

if [ ! -f "$PJSIP_CONF" ]; then
    error "Файл $PJSIP_CONF не найден. Установите Asterisk."
    exit 1
fi

if [ ! -f "$EXTENSIONS_CONF" ]; then
    error "Файл $EXTENSIONS_CONF не найден. Установите Asterisk."
    exit 1
fi

info "Обновляем конфигурации..."

# Создаём резервные копии
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$PJSIP_CONF" "$BACKUP_DIR/pjsip.conf.bak"
cp "$EXTENSIONS_CONF" "$BACKUP_DIR/extensions.conf.bak"
info "Резервные копии созданы в $BACKUP_DIR"

# Обновляем pjsip.conf
info "Обновляем pjsip.conf..."
sed -i "s/YOUR_SIP_LOGIN_HERE/$SIP_LOGIN/g" "$PJSIP_CONF"
sed -i "s/YOUR_SIP_PASSWORD_HERE/$SIP_PASSWORD/g" "$PJSIP_CONF"
sed -i "s/YOUR_PUBLIC_IP_HERE/$PUBLIC_IP/g" "$PJSIP_CONF"

# Удаляем или комментируем identify секцию, если IP не указан
if grep -q "IP_ADDRESS_OF_NOVOFON_HERE" "$PJSIP_CONF"; then
    warn "Секция identify содержит placeholder. Закомментируйте её вручную, если не знаете IP NovoFon."
fi

# Обновляем extensions.conf
info "Обновляем extensions.conf..."
sed -i "s/YOUR_CALLER_ID_HERE/$CALLER_ID/g" "$EXTENSIONS_CONF"

# Проверяем синтаксис
info "Проверяем синтаксис конфигураций..."
if asterisk -rx "pjsip reload" 2>&1 | grep -q "error"; then
    error "Ошибка в pjsip.conf! Проверьте конфигурацию."
    exit 1
fi

if asterisk -rx "dialplan reload" 2>&1 | grep -q "error"; then
    error "Ошибка в extensions.conf! Проверьте конфигурацию."
    exit 1
fi

info "✅ Конфигурации обновлены"

# Перезагружаем Asterisk
info "Перезагружаем Asterisk..."
systemctl restart asterisk
sleep 2

# Проверяем статус
if systemctl is-active --quiet asterisk; then
    info "✅ Asterisk запущен"
else
    error "❌ Asterisk не запустился. Проверьте логи: journalctl -u asterisk"
    exit 1
fi

# Проверяем регистрацию
info "Проверяем SIP регистрацию..."
sleep 3
asterisk -rx "pjsip show endpoints" | grep -q "novofon" && \
    info "✅ Endpoint novofon найден" || \
    warn "⚠️  Endpoint novofon не найден. Проверьте регистрацию."

# Проверяем ARI
info "Проверяем ARI..."
if curl -s -u novofon_bot:novofon_bot_2024 http://localhost:8088/ari/asterisk/info > /dev/null 2>&1; then
    info "✅ ARI доступен"
else
    warn "⚠️  ARI недоступен. Проверьте настройки ARI."
fi

echo ""
info "✅ Настройка завершена!"
echo ""
info "Следующие шаги:"
info "1. Проверь регистрацию: sudo asterisk -rx 'pjsip show endpoints'"
info "2. Проверь логи: sudo journalctl -u novofon-bot -f"
info "3. Сделай тестовый звонок через API:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate \\"
info "     -H 'Content-Type: application/json' \\"
info "     -d '{\"phone\": \"+79991234567\"}'"
echo ""

