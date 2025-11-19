#!/bin/bash
# Диагностика сетевых проблем с SIP

echo "=========================================="
echo "🌐 Диагностика сетевых проблем с SIP"
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
    error "Запустите с sudo: sudo bash diagnose_network.sh"
    exit 1
fi

SIP_SERVER="sip.novofon.ru"
SIP_PORT="5060"

# 1. Проверяем DNS
info "1. Проверяем DNS резолвинг $SIP_SERVER..."
if command -v dig &> /dev/null; then
    DNS_RESULT=$(dig +short $SIP_SERVER 2>/dev/null)
    if [ -n "$DNS_RESULT" ]; then
        info "   ✅ DNS резолвится: $DNS_RESULT"
    else
        error "   ❌ DNS НЕ резолвится!"
    fi
elif command -v nslookup &> /dev/null; then
    DNS_RESULT=$(nslookup $SIP_SERVER 2>/dev/null | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
    if [ -n "$DNS_RESULT" ]; then
        info "   ✅ DNS резолвится: $DNS_RESULT"
    else
        error "   ❌ DNS НЕ резолвится!"
    fi
else
    warn "   dig и nslookup не найдены, проверяем через ping..."
    if ping -c 1 -W 2 $SIP_SERVER &> /dev/null; then
        info "   ✅ Сервер доступен (ping)"
    else
        error "   ❌ Сервер НЕ доступен (ping)"
    fi
fi
echo ""

# 2. Проверяем доступность порта 5060 UDP
info "2. Проверяем доступность порта $SIP_PORT UDP..."
if command -v nc &> /dev/null; then
    timeout 3 nc -u -v -z $SIP_SERVER $SIP_PORT 2>&1 | head -3 | sed 's/^/   /'
    NC_EXIT=$?
    if [ $NC_EXIT -eq 0 ]; then
        info "   ✅ Порт $SIP_PORT UDP доступен"
    else
        warn "   ⚠️  Порт $SIP_PORT UDP может быть недоступен (это нормально для UDP)"
    fi
elif command -v nmap &> /dev/null; then
    info "   Проверяем через nmap..."
    nmap -sU -p $SIP_PORT $SIP_SERVER 2>&1 | grep -E "open|filtered|closed" | sed 's/^/   /'
else
    warn "   nc и nmap не найдены, пропускаем проверку порта"
fi
echo ""

# 3. Проверяем firewall (ufw)
info "3. Проверяем firewall (ufw)..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    echo "$UFW_STATUS" | sed 's/^/   /'
    
    if echo "$UFW_STATUS" | grep -q "active"; then
        info "   UFW активен, проверяем правила для порта $SIP_PORT..."
        UFW_RULES=$(ufw status | grep -E "5060|SIP|5060/udp")
        if [ -n "$UFW_RULES" ]; then
            echo "$UFW_RULES" | sed 's/^/   /'
        else
            warn "   ⚠️  Правил для порта $SIP_PORT не найдено!"
            info "   Нужно добавить: ufw allow out $SIP_PORT/udp"
        fi
    else
        info "   UFW не активен"
    fi
else
    warn "   UFW не установлен"
fi
echo ""

# 4. Проверяем iptables
info "4. Проверяем iptables правила для исходящего трафика на $SIP_PORT UDP..."
if command -v iptables &> /dev/null; then
    IPTABLES_OUTPUT=$(iptables -L OUTPUT -n -v 2>/dev/null | grep -E "5060|udp" | head -5)
    if [ -n "$IPTABLES_OUTPUT" ]; then
        echo "$IPTABLES_OUTPUT" | sed 's/^/   /'
    else
        warn "   ⚠️  Правил для порта $SIP_PORT UDP в OUTPUT не найдено"
    fi
else
    warn "   iptables не доступен"
fi
echo ""

# 5. Проверяем, может ли Asterisk отправить OPTIONS
info "5. Проверяем, может ли Asterisk отправить OPTIONS запрос..."
OPTIONS_RESULT=$(timeout 5 asterisk -rx "pjsip send options novofon-endpoint" 2>&1)
if [ $? -eq 0 ]; then
    echo "$OPTIONS_RESULT" | sed 's/^/   /'
    if echo "$OPTIONS_RESULT" | grep -qi "200 OK\|sent"; then
        info "   ✅ OPTIONS запрос отправлен успешно"
    else
        warn "   ⚠️  OPTIONS запрос не дал результата"
    fi
else
    warn "   ⚠️  Не удалось отправить OPTIONS запрос"
fi
echo ""

# 6. Проверяем сетевые интерфейсы
info "6. Проверяем сетевые интерфейсы и внешний IP..."
EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
if [ -n "$EXTERNAL_IP" ]; then
    info "   Внешний IP: $EXTERNAL_IP"
else
    warn "   Не удалось определить внешний IP"
fi

INTERFACES=$(ip -4 addr show | grep -E "inet.*eth|inet.*ens" | awk '{print $2, $NF}')
if [ -n "$INTERFACES" ]; then
    info "   Сетевые интерфейсы:"
    echo "$INTERFACES" | sed 's/^/   /'
fi
echo ""

# 7. Проверяем NAT настройки в pjsip.conf
info "7. Проверяем NAT настройки в pjsip.conf..."
if grep -q "external_media_address\|external_signaling_address" /etc/asterisk/pjsip.conf; then
    info "   ✅ NAT настройки найдены:"
    grep -E "external_media_address|external_signaling_address" /etc/asterisk/pjsip.conf | sed 's/^/   /'
else
    warn "   ⚠️  NAT настройки не найдены"
fi
echo ""

# 8. Тест отправки UDP пакета вручную
info "8. Тест отправки UDP пакета вручную..."
if command -v timeout &> /dev/null && command -v nc &> /dev/null; then
    info "   Отправляем тестовый UDP пакет на $SIP_SERVER:$SIP_PORT..."
    echo "TEST" | timeout 2 nc -u -w 1 $SIP_SERVER $SIP_PORT 2>&1 | head -2 | sed 's/^/   /'
    if [ $? -eq 0 ]; then
        info "   ✅ UDP пакет отправлен (ответ не обязателен для UDP)"
    else
        warn "   ⚠️  Не удалось отправить UDP пакет"
    fi
else
    warn "   timeout или nc не найдены, пропускаем тест"
fi
echo ""

# 9. Рекомендации
info "9. Рекомендации по исправлению:"
echo ""
info "   Если порт $SIP_PORT UDP заблокирован, выполни:"
info "   sudo ufw allow out $SIP_PORT/udp"
info "   sudo ufw allow out 10000:20000/udp"
info ""
info "   Если нужно добавить правило в iptables:"
info "   sudo iptables -I OUTPUT -p udp --dport $SIP_PORT -j ACCEPT"
info "   sudo iptables -I OUTPUT -p udp --dport 10000:20000 -j ACCEPT"
info ""
info "   После исправления перезагрузи Asterisk:"
info "   sudo systemctl restart asterisk"

echo ""
info "Диагностика завершена!"

