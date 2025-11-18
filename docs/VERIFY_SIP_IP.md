# ✅ Верификация IP для SIP-транка

## Что происходит

NovoFon требует совершить тестовый звонок с IP сервера, чтобы:
- Подтвердить, что IP адрес правильный
- Активировать SIP-транк
- Разрешить входящие звонки

Это нормальная процедура безопасности.

---

## Как сделать тестовый звонок

### Вариант 1: Через Asterisk CLI (быстро)

```bash
# Зайди в консоль Asterisk
sudo asterisk -rvvv

# В консоли Asterisk выполни:
originate PJSIP/79991234567@novofon extension 100@test
```

Где:
- `79991234567` - номер, на который звонить (твой номер или тестовый)
- `novofon` - имя SIP транка (из pjsip.conf)

### Вариант 2: Через API бота (если уже настроен)

```bash
curl -X POST http://109.73.192.126/api/calls/initiate \
  -H "Content-Type: application/json" \
  -d '{"phone": "+79991234567"}'
```

### Вариант 3: Через ARI напрямую

```bash
curl -X POST \
  -u novofon_bot:novofon_bot_2024 \
  http://localhost:8088/ari/channels \
  -H "Content-Type: application/json" \
  -d '{
    "endpoint": "PJSIP/79991234567@novofon",
    "app": "novofon_bot"
  }'
```

---

## Если Asterisk ещё не настроен

### Быстрая настройка для теста:

1. **Создай минимальный pjsip.conf:**

```bash
sudo nano /etc/asterisk/pjsip.conf
```

Добавь (замени на свои данные):
```ini
[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060

[novofon]
type = endpoint
context = from-internal
disallow = all
allow = ulaw
allow = alaw
aors = novofon
auth = novofon

[novofon]
type = aor
contact = sip:sip.novofon.ru

[novofon]
type = auth
auth_type = userpass
username = ТВОЙ_SIP_ЛОГИН
password = ТВОЙ_SIP_ПАРОЛЬ
```

2. **Перезагрузи Asterisk:**

```bash
sudo systemctl restart asterisk
sudo asterisk -rx "pjsip reload"
```

3. **Сделай тестовый звонок:**

```bash
sudo asterisk -rvvv
# В консоли:
originate PJSIP/79991234567@novofon extension 100@test
```

---

## Проверка результата

После звонка:

1. **Вернись в личный кабинет NovoFon**
2. **Проверь статус SIP-транка** - должен стать активным
3. **Проверь логи Asterisk:**

```bash
sudo tail -f /var/log/asterisk/full
```

Должны быть строки типа:
```
-- Executing [100@test:1] NoOp("PJSIP/...", "=== Test extension ===") in new stack
```

---

## Если не получается

### Проблема: Asterisk не может дозвониться

1. **Проверь регистрацию:**
```bash
sudo asterisk -rx "pjsip show endpoints"
```

2. **Проверь SIP трафик:**
```bash
sudo tcpdump -i any -n port 5060
```

3. **Проверь логи:**
```bash
sudo tail -f /var/log/asterisk/full
```

### Проблема: NovoFon не видит звонок

- Убедись, что **адреса терминации** в личном кабинете правильные (109.73.192.126)
- Проверь, что **firewall** не блокирует порт 5060
- Попробуй позвонить на другой номер (например, на свой мобильный)

---

## После успешной верификации

1. NovoFon активирует транк
2. Ты получишь логин и пароль (если ещё не получил)
3. Можно настраивать бота:

```bash
cd ~/NovoFon_Bot
sudo bash setup_asterisk_calls.sh
```

