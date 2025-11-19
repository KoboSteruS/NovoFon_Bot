#!/bin/bash
# Полная настройка NovoFon через chan_sip (как в документации)

echo "=========================================="
echo "📞 Настройка NovoFon через chan_sip"
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
    error "Запустите с sudo: sudo bash setup_novofon_chan_sip.sh"
    exit 1
fi

# SIP данные NovoFon
SIP_USERNAME="606147"
SIP_PASSWORD="gMLPTrc9h3"
SIP_SERVER="sip.novofon.ru"
SIP_PORT="5060"
CALLER_ID="+79675558164"

info "Настраиваем NovoFon через chan_sip (как в документации)..."
info "Логин: $SIP_USERNAME"
info "Сервер: $SIP_SERVER:$SIP_PORT"
echo ""

# Резервная копия
BACKUP_DIR="/etc/asterisk/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/asterisk/modules.conf "$BACKUP_DIR/modules.conf.bak" 2>/dev/null || true
cp /etc/asterisk/sip.conf "$BACKUP_DIR/sip.conf.bak" 2>/dev/null || true
cp /etc/asterisk/extensions.conf "$BACKUP_DIR/extensions.conf.bak" 2>/dev/null || true
info "Резервная копия создана в $BACKUP_DIR"
echo ""

# 1. Настраиваем modules.conf - отключаем PJSIP, включаем chan_sip
info "1. Настраиваем modules.conf - отключаем PJSIP, включаем chan_sip..."

# Проверяем, есть ли уже настройки
if grep -q "noload => res_pjsip" /etc/asterisk/modules.conf; then
    info "   PJSIP уже отключён"
else
    # Добавляем отключение PJSIP в начало файла
    if [ ! -f /etc/asterisk/modules.conf ] || [ ! -s /etc/asterisk/modules.conf ]; then
        cat > /etc/asterisk/modules.conf <<EOF
; Asterisk modules configuration

; Отключаем PJSIP для NovoFon
noload => res_pjsip.so
noload => res_pjsip_transport_udp.so
noload => res_pjsip_transport_websocket.so
noload => res_pjsip_authenticator_digest.so
noload => res_pjsip_endpoint_identifier_ip.so
noload => res_pjsip_endpoint_identifier_user.so
noload => res_pjsip_aor.so
noload => res_pjsip_registrar.so
noload => res_pjsip_session.so
noload => res_pjsip.so

; Включаем chan_sip
load => chan_sip.so

EOF
    else
        # Добавляем в начало файла
        sed -i '1i; Отключаем PJSIP для NovoFon\nnoload => res_pjsip.so\nnoload => res_pjsip_transport_udp.so\nnoload => res_pjsip_transport_websocket.so\nnoload => res_pjsip_authenticator_digest.so\nnoload => res_pjsip_endpoint_identifier_ip.so\nnoload => res_pjsip_endpoint_identifier_user.so\nnoload => res_pjsip_aor.so\nnoload => res_pjsip_registrar.so\nnoload => res_pjsip_session.so\n; Включаем chan_sip\nload => chan_sip.so\n' /etc/asterisk/modules.conf
    fi
    info "   ✅ PJSIP отключён, chan_sip включён"
fi

# Проверяем, что chan_sip загружен
if ! grep -q "load => chan_sip.so" /etc/asterisk/modules.conf; then
    echo "load => chan_sip.so" >> /etc/asterisk/modules.conf
    info "   ✅ chan_sip добавлен"
fi
echo ""

# 2. Настраиваем sip.conf
info "2. Настраиваем sip.conf по документации NovoFon..."

# Создаём или обновляем sip.conf
cat > /etc/asterisk/sip.conf <<EOF
;
; SIP Configuration для NovoFon (chan_sip)
; Настроено по официальной документации NovoFon
;

[general]
; Общие настройки
srvlookup=yes
bindport=5060
bindaddr=0.0.0.0
allowguest=no
context=default
allowoverlap=no
udpbindaddr=0.0.0.0
tcpenable=no
tcpbindaddr=0.0.0.0
transport=udp

; NAT настройки
externip=109.73.192.126
localnet=192.168.0.0/255.255.0.0
localnet=10.0.0.0/255.0.0.0
localnet=172.16.0.0/255.240.0.0
nat=force_rport,comedia

; Регистрация на NovoFon
register => $SIP_USERNAME:$SIP_PASSWORD@$SIP_SERVER/$SIP_USERNAME

; ==========================================
; NOVOFON PEER (по документации)
; ==========================================

[$SIP_USERNAME]
type=peer
host=$SIP_SERVER
defaultuser=$SIP_USERNAME
fromuser=$SIP_USERNAME
fromdomain=$SIP_SERVER
secret=$SIP_PASSWORD
insecure=invite,port
context=from-novofon
disallow=all
allow=ulaw
allow=alaw
nat=force_rport,comedia
qualify=400
directmedia=no
trunkname=$SIP_USERNAME
callbackextension=$SIP_USERNAME
canreinvite=no
dtmfmode=rfc2833

EOF

info "   ✅ sip.conf настроен"
echo ""

# 3. Обновляем extensions.conf для работы с chan_sip
info "3. Обновляем extensions.conf для работы с chan_sip..."

# Удаляем старую секцию outgoing если есть
if grep -q "^\[outgoing\]" /etc/asterisk/extensions.conf; then
    python3 << 'PYEOF'
with open('/etc/asterisk/extensions.conf', 'r') as f:
    lines = f.readlines()

output = []
skip = False
for line in lines:
    if line.strip().startswith('[outgoing]'):
        skip = True
        continue
    if skip and line.strip().startswith('[') and not line.strip().startswith('[outgoing]'):
        skip = False
        output.append(line)
    elif not skip:
        output.append(line)

with open('/etc/asterisk/extensions.conf', 'w') as f:
    f.writelines(output)
PYEOF
fi

# Добавляем правильные секции для chan_sip
cat >> /etc/asterisk/extensions.conf <<EOF

;=============== ВХОДЯЩИЕ ЗВОНКИ ОТ NOVOFON (chan_sip) ===============

[from-novofon]
; Все входящие звонки попадают в Stasis приложение
exten => _X.,1,NoOp(=== Incoming call from NovoFon ===)
 same => n,NoOp(CallerID: \${CALLERID(num)})
 same => n,NoOp(Destination: \${EXTEN})
 same => n,Set(CHANNEL(language)=ru)
 same => n,Stasis(novofon_bot,incoming,\${EXTEN})
 same => n,Hangup()

; Обработка неизвестных номеров
exten => s,1,NoOp(=== Unknown incoming call ===)
 same => n,Stasis(novofon_bot,incoming,unknown)
 same => n,Hangup()

;=============== ИСХОДЯЩИЕ ЗВОНКИ ЧЕРЕЗ NOVOFON (chan_sip) ===============

[outgoing]
; Реальный звонок через NovoFon на внешний номер
; Используется ботом через ARI: Local/{phone}@outgoing
exten => _X.,1,NoOp(=== Outgoing call to \${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=$CALLER_ID)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,NoOp(Original number: \${EXTEN})
 ; Форматируем номер: убираем все нецифровые символы
 same => n,Set(RAW_NUM=\${EXTEN})
 same => n,Set(RAW_NUM=\${RAW_NUM//[^0-9]/})
 same => n,NoOp(Cleaned number: \${RAW_NUM}, length: \${LEN(\${RAW_NUM})})
 ; Если номер начинается с 7 и длина 11 - добавляем +
 same => n,GotoIf(\$["\${RAW_NUM:0:1}" = "7"]?check_len)
 same => n,GotoIf(\$["\${RAW_NUM:0:1}" = "8"]?convert_8)
 same => n,GotoIf(\$["\${RAW_NUM:0:2}" = "+7"]?already_plus)
 ; Если не начинается с 7 или 8 - добавляем +7
 same => n,Set(OUTBOUND_NUM=+7\${RAW_NUM})
 same => n,Goto(dial)
 ; Проверяем длину для номеров начинающихся с 7
 same => n(check_len),GotoIf(\$["\${LEN(\${RAW_NUM})}" = "11"]?add_plus_to_7)
 same => n,GotoIf(\$["\${LEN(\${RAW_NUM})}" = "10"]?add_plus_to_7)
 same => n,Set(OUTBOUND_NUM=+\${RAW_NUM})
 same => n,Goto(dial)
 same => n(add_plus_to_7),Set(OUTBOUND_NUM=+\${RAW_NUM})
 same => n,Goto(dial)
 ; Конвертируем 8 в +7
 same => n(convert_8),Set(OUTBOUND_NUM=+7\${RAW_NUM:1})
 same => n,Goto(dial)
 ; Уже с +7
 same => n(already_plus),Set(OUTBOUND_NUM=\${RAW_NUM})
 ; ВАЖНО: Используем SIP вместо PJSIP для chan_sip
 same => n(dial),NoOp(Formatted number for NovoFon: \${OUTBOUND_NUM})
 same => n,NoOp(Full number length: \${LEN(\${OUTBOUND_NUM})})
 same => n,NoOp(Calling via SIP/\${OUTBOUND_NUM}@$SIP_USERNAME)
 same => n,Set(DIAL_TARGET=\${OUTBOUND_NUM})
 same => n,NoOp(Dial target: \${DIAL_TARGET})
 same => n,Dial(SIP/\${DIAL_TARGET}@$SIP_USERNAME,60,Tt)
 same => n,NoOp(Dial ended with status: \${DIALSTATUS}, cause: \${HANGUPCAUSE})
 same => n,Hangup()

EOF

info "   ✅ extensions.conf обновлён для chan_sip"
echo ""

# 4. Перезапускаем Asterisk
info "4. Перезапускаем Asterisk для применения изменений..."
systemctl restart asterisk
sleep 5
info "✅ Asterisk перезапущен"
echo ""

# 5. Проверяем регистрацию
info "5. Проверяем регистрацию на NovoFon..."
echo ""
REG_STATUS=$(asterisk -rx "sip show registry" 2>/dev/null | grep -i "novofon\|$SIP_USERNAME")
if [ -n "$REG_STATUS" ]; then
    info "   Статус регистрации:"
    echo "$REG_STATUS" | sed 's/^/   /'
    if echo "$REG_STATUS" | grep -qi "Registered"; then
        info "   ✅ Регистрация успешна!"
    else
        warn "   ⚠️  Регистрация не прошла, ждём ещё 10 секунд..."
        sleep 10
        REG_STATUS2=$(asterisk -rx "sip show registry" 2>/dev/null | grep -i "novofon\|$SIP_USERNAME")
        if echo "$REG_STATUS2" | grep -qi "Registered"; then
            info "   ✅ Регистрация успешна!"
        else
            warn "   ⚠️  Регистрация всё ещё не прошла"
            info "   Проверь логи: sudo tail -50 /var/log/asterisk/messages | grep -i register"
        fi
    fi
else
    warn "   ⚠️  Регистрация не найдена"
    info "   Проверь логи: sudo tail -50 /var/log/asterisk/messages | grep -i register"
fi
echo ""

# 6. Проверяем SIP peers
info "6. Проверяем SIP peers..."
PEER_STATUS=$(asterisk -rx "sip show peers" 2>/dev/null | grep -i "$SIP_USERNAME")
if [ -n "$PEER_STATUS" ]; then
    info "   Статус peer:"
    echo "$PEER_STATUS" | sed 's/^/   /'
else
    warn "   ⚠️  Peer не найден"
fi
echo ""

# 7. Инструкции для теста
info "7. Теперь можно протестировать:"
echo ""
info "   Проверка регистрации:"
info "   sudo asterisk -rx \"sip show registry\""
echo ""
info "   Проверка peers:"
info "   sudo asterisk -rx \"sip show peers\""
echo ""
info "   Тест исходящего звонка:"
info "   sudo asterisk -rx \"channel originate Local/79522675444@outgoing application Playback hello-world\""
echo ""
info "   Или через API бота:"
info "   curl -X POST http://109.73.192.126/api/calls/initiate -H \"Content-Type: application/json\" -d '{\"phone\": \"+79522675444\"}'"
echo ""
info "   Проверка SIP трафика:"
info "   sudo tcpdump -i any -n port 5060 -v | grep -E \"INVITE|REGISTER|sip.novofon\""
echo ""

info "✅ Настройка завершена!"
info ""
info "Теперь NovoFon работает через chan_sip, как в официальной документации!"
info "После регистрации исходящие звонки должны работать автоматически!"

