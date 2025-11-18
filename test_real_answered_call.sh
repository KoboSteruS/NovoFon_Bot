#!/bin/bash
# Тестовый звонок на реальный номер с ожиданием ответа

echo "=========================================="
echo "📞 Тестовый звонок на реальный номер"
echo "=========================================="
echo ""

read -p "Введи номер, на который позвонить (например +79991234567): " TEST_NUMBER
TEST_NUMBER=$(echo $TEST_NUMBER | tr -d '+ ')

echo ""
echo "Делаю звонок на $TEST_NUMBER..."
echo "ВАЖНО: Ответь на звонок, чтобы NovoFon зафиксировал успешное соединение!"
echo ""

# Создаём extension для звонка с ожиданием ответа
sudo tee -a /etc/asterisk/extensions.conf > /dev/null <<EOF

[test-real-call]
; Звонок с ожиданием ответа абонента
exten => _X.,1,NoOp(=== Real call to \${EXTEN} ===)
 same => n,Set(CALLERID(num)=+79581114585)
 same => n,Set(CALLERID(name)=NovoFon Test)
 same => n,Dial(PJSIP/\${EXTEN}@novofon,60)
 same => n,NoOp(Call ended with status: \${DIALSTATUS})
 same => n,Hangup()
EOF

sudo asterisk -rx "dialplan reload" > /dev/null 2>&1

echo "Звоню через Asterisk..."
sudo asterisk -rx "channel originate Local/${TEST_NUMBER}@test-real-call application Playback hello-world" &
CALL_PID=$!

echo ""
echo "Звонок инициирован. PID: $CALL_PID"
echo "Ответь на звонок на телефоне!"
echo ""
echo "После звонка проверь статус транка в личном кабинете NovoFon"
echo ""

wait $CALL_PID 2>/dev/null || true

echo ""
echo "Звонок завершён. Проверь статус транка в личном кабинете."

