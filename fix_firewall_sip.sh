#!/bin/bash
# Автоматическое исправление firewall для SIP

echo "=========================================="
echo "🔥 Исправление firewall для SIP"
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
    error "Запустите с sudo: sudo bash fix_firewall_sip.sh"
    exit 1
fi

# 1. UFW
info "1. Настраиваем UFW для SIP..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        info "   UFW активен, добавляем правила для SIP..."
        
        # Исходящий трафик на SIP порт
        ufw allow out 5060/udp > /dev/null 2>&1
        info "   ✅ Добавлено правило: ufw allow out 5060/udp"
        
        # Исходящий трафик на RTP порты
        ufw allow out 10000:20000/udp > /dev/null 2>&1
        info "   ✅ Добавлено правило: ufw allow out 10000:20000/udp"
        
        # Входящий трафик на SIP порт (для входящих звонков)
        ufw allow in 5060/udp > /dev/null 2>&1
        info "   ✅ Добавлено правило: ufw allow in 5060/udp"
        
        # Входящий трафик на RTP порты
        ufw allow in 10000:20000/udp > /dev/null 2>&1
        info "   ✅ Добавлено правило: ufw allow in 10000:20000/udp"
        
        ufw reload > /dev/null 2>&1
        info "   ✅ UFW перезагружен"
    else
        warn "   UFW не активен, пропускаем"
    fi
else
    warn "   UFW не установлен, пропускаем"
fi
echo ""

# 2. iptables
info "2. Настраиваем iptables для SIP..."
if command -v iptables &> /dev/null; then
    # Проверяем, есть ли уже правила
    if ! iptables -C OUTPUT -p udp --dport 5060 -j ACCEPT 2>/dev/null; then
        iptables -I OUTPUT -p udp --dport 5060 -j ACCEPT
        info "   ✅ Добавлено правило iptables: OUTPUT -> 5060/udp"
    else
        info "   ✅ Правило OUTPUT -> 5060/udp уже существует"
    fi
    
    if ! iptables -C OUTPUT -p udp --dport 10000:20000 -j ACCEPT 2>/dev/null; then
        iptables -I OUTPUT -p udp --dport 10000:20000 -j ACCEPT
        info "   ✅ Добавлено правило iptables: OUTPUT -> 10000:20000/udp"
    else
        info "   ✅ Правило OUTPUT -> 10000:20000/udp уже существует"
    fi
    
    # Входящий трафик
    if ! iptables -C INPUT -p udp --dport 5060 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport 5060 -j ACCEPT
        info "   ✅ Добавлено правило iptables: INPUT -> 5060/udp"
    else
        info "   ✅ Правило INPUT -> 5060/udp уже существует"
    fi
    
    if ! iptables -C INPUT -p udp --dport 10000:20000 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport 10000:20000 -j ACCEPT
        info "   ✅ Добавлено правило iptables: INPUT -> 10000:20000/udp"
    else
        info "   ✅ Правило INPUT -> 10000:20000/udp уже существует"
    fi
    
    # Сохраняем правила (если установлен iptables-persistent)
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save > /dev/null 2>&1
        info "   ✅ Правила iptables сохранены"
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        info "   ✅ Правила iptables сохранены"
    fi
else
    warn "   iptables не доступен, пропускаем"
fi
echo ""

# 3. Проверяем результат
info "3. Проверяем результат..."
echo ""

if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    info "   UFW правила для SIP:"
    ufw status | grep -E "5060|10000:20000" | sed 's/^/   /'
fi

if command -v iptables &> /dev/null; then
    info "   iptables правила для SIP (OUTPUT):"
    iptables -L OUTPUT -n -v | grep -E "5060|10000:20000" | head -5 | sed 's/^/   /'
fi

echo ""
info "✅ Firewall настроен для SIP!"
echo ""
info "Теперь попробуй снова сделать тестовый звонок:"
info "   sudo bash test_call_final.sh"
info ""
info "Или через API:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate -H \"Content-Type: application/json\" -d '{\"phone\": \"+79522675444\"}'"

