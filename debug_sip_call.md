# 🔍 Диагностика SIP звонка

## Проблема
Звонок создаётся, но не уходит в NovoFon - остаётся внутри Asterisk.

## Что проверить

### 1. Проверь SIP трафик (в отдельном терминале)

```bash
sudo tcpdump -i any -n port 5060 -v
```

Затем сделай звонок. Должны быть пакеты:
- `INVITE` к `sip.novofon.ru`
- Ответы от NovoFon

Если пакетов нет → звонок не уходит.

### 2. Проверь логи Asterisk детально

```bash
sudo tail -f /var/log/asterisk/full | grep -i "invite\|novofon\|sip"
```

Ищи:
- `INVITE` запросы
- Ошибки аутентификации
- "No route to destination"

### 3. Проверь endpoint

```bash
sudo asterisk -rx "pjsip show endpoints"
sudo asterisk -rx "pjsip show aors"
```

### 4. Возможная проблема: формат Dial()

Попробуй другой формат:

```bash
# В консоли Asterisk
channel originate PJSIP/79991234567@novofon extension s@outgoing
```

Или через ARI:

```bash
curl -X POST \
  -u novofon_bot:novofon_bot_2024 \
  http://localhost:8088/ari/channels \
  -H "Content-Type: application/json" \
  -d '{
    "endpoint": "PJSIP/79991234567@novofon",
    "app": "novofon_bot",
    "callerId": "+79581114585"
  }'
```

