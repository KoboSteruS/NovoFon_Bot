#!/bin/bash
# Проверка SIP трафика при звонке

echo "=========================================="
echo "📞 Проверка SIP трафика"
echo "=========================================="
echo ""

echo "Запусти в ОТДЕЛЬНОМ терминале:"
echo "  sudo tcpdump -i any -n port 5060 -v | grep -E 'INVITE|200|487|CANCEL|BYE|ACK'"
echo ""
echo "Затем в ЭТОМ терминале сделай звонок:"
echo "  sudo asterisk -rx \"channel originate Local/79522675444@outgoing application Playback hello-world\""
echo ""
echo "Смотри в первом терминале - должны быть:"
echo "  - INVITE к sip.novofon.ru"
echo "  - 200 OK от NovoFon (звонок принят)"
echo "  - 487 Request Terminated или CANCEL (если NovoFon не может дозвониться)"
echo ""

