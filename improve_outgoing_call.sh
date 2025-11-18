#!/bin/bash
# Улучшение extension для исходящих звонков

set -e

echo "=========================================="
echo "📞 Улучшение extension для звонков"
echo "=========================================="
echo ""

# Цвета
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Проверяем, есть ли секция outgoing
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    info "Секция [outgoing] найдена, обновляем..."
    
    # Удаляем старую секцию outgoing
    sudo sed -i '/^\[outgoing\]/,/^$/d' /etc/asterisk/extensions.conf
    
    # Добавляем улучшенную секцию
    sudo tee -a /etc/asterisk/extensions.conf > /dev/null <<'EOF'

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Увеличено время ожидания до 60 секунд
exten => _X.,1,NoOp(=== Outgoing call to ${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=+79581114585)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Calling ${EXTEN} via PJSIP/novofon, timeout 60s)
 same => n,Dial(PJSIP/${EXTEN}@novofon,60,Tt)
 same => n,NoOp(Dial ended with status: ${DIALSTATUS})
 same => n,Hangup()
EOF
    
    info "✅ Секция [outgoing] обновлена (timeout 60s)"
else
    info "Секция [outgoing] не найдена, создаём..."
    sudo tee -a /etc/asterisk/extensions.conf > /dev/null <<'EOF'

[outgoing]
; Реальный звонок через NovoFon на внешний номер
exten => _X.,1,NoOp(=== Outgoing call to ${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=+79581114585)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,Dial(PJSIP/${EXTEN}@novofon,60,Tt)
 same => n,Hangup()
EOF
    
    info "✅ Секция [outgoing] создана"
fi

# Перезагружаем dialplan
info "Перезагружаем dialplan..."
sudo asterisk -rx "dialplan reload" > /dev/null 2>&1

echo ""
info "✅ Готово!"
echo ""
info "Теперь попробуй:"
info "  sudo asterisk -rvvv"
info "  channel originate Local/79991234567@outgoing application Playback hello-world"
info ""
info "ВАЖНО: Убедись, что номер активен в NovoFon!"
echo ""

