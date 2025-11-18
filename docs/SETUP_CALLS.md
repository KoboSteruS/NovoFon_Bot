# 📞 Настройка входящих и исходящих звонков

## Что нужно сделать

### 1. Настроить Asterisk SIP транк к NovoFon

#### Шаг 1: Получить данные от NovoFon
Тебе нужны:
- SIP логин (username)
- SIP пароль
- SIP сервер (обычно `sip.novofon.ru`)
- Твой номер (Caller ID)

#### Шаг 2: Настроить PJSIP

Отредактируй `/etc/asterisk/pjsip.conf`:

```bash
sudo nano /etc/asterisk/pjsip.conf
```

Замени в файле:
- `YOUR_PUBLIC_IP_HERE` → твой публичный IP (109.73.192.126)
- `YOUR_SIP_LOGIN_HERE` → твой SIP логин от NovoFon
- `YOUR_SIP_PASSWORD_HERE` → твой SIP пароль
- `IP_ADDRESS_OF_NOVOFON_HERE` → IP NovoFon (или удали секцию identify, если не знаешь)

#### Шаг 3: Настроить Dialplan

Отредактируй `/etc/asterisk/extensions.conf`:

```bash
sudo nano /etc/asterisk/extensions.conf
```

Замени:
- `YOUR_CALLER_ID_HERE` → твой номер (например, +79581114585)

#### Шаг 4: Перезагрузить Asterisk

```bash
sudo systemctl restart asterisk
sudo asterisk -rx "pjsip reload"
sudo asterisk -rx "dialplan reload"
```

#### Шаг 5: Проверить подключение

```bash
# Проверить регистрацию
sudo asterisk -rx "pjsip show endpoints"

# Проверить ARI
curl -u novofon_bot:novofon_bot_2024 http://localhost:8088/ari/asterisk/info
```

---

### 2. Исходящие звонки (бот звонит тебе)

#### Через API:

```bash
curl -X POST http://109.73.192.126/api/calls/initiate \
  -H "Content-Type: application/json" \
  -d '{"phone": "+79991234567"}'
```

Или через Swagger UI:
- Открой `http://109.73.192.126/docs`
- Найди `POST /api/calls/initiate`
- Введи номер и нажми Execute

#### Что происходит:
1. Бот создаёт запись в БД
2. Через Asterisk ARI инициирует звонок через SIP транк
3. NovoFon дозванивается до указанного номера
4. Когда абонент отвечает, бот начинает диалог

---

### 3. Входящие звонки (ты звонишь боту)

#### Настройка в NovoFon:
1. Зайди в личный кабинет NovoFon
2. Найди настройки SIP или маршрутизации
3. Настрой переадресацию входящих звонков на твой Asterisk сервер:
   - IP: 109.73.192.126
   - Порт: 5060 (UDP)
   - Или используй SIP URI: `sip:YOUR_SIP_LOGIN@109.73.192.126:5060`

#### Что происходит:
1. NovoFon получает входящий звонок
2. Переадресовывает его на твой Asterisk
3. Asterisk получает звонок в контекст `from-novofon`
4. Dialplan отправляет звонок в Stasis приложение `novofon_bot`
5. Бот отвечает и начинает диалог

---

### 4. Проверка работы

#### Проверить логи бота:
```bash
sudo journalctl -u novofon-bot -f
```

#### Проверить логи Asterisk:
```bash
sudo tail -f /var/log/asterisk/full
```

#### Проверить ARI подключение:
```bash
# Проверить, что приложение зарегистрировано
curl -u novofon_bot:novofon_bot_2024 \
  http://localhost:8088/ari/applications/novofon_bot
```

#### Тестовый звонок через Asterisk CLI:
```bash
sudo asterisk -rvvv
# В консоли Asterisk:
originate PJSIP/79991234567@novofon extension s@from-internal
```

---

### 5. Устранение проблем

#### Проблема: Asterisk не подключается к NovoFon
```bash
# Проверить регистрацию
sudo asterisk -rx "pjsip show registrations"

# Проверить endpoints
sudo asterisk -rx "pjsip show endpoints"

# Проверить детали
sudo asterisk -rx "pjsip show endpoint novofon"
```

#### Проблема: ARI не получает события
```bash
# Проверить, что ARI включён
sudo asterisk -rx "ari show status"

# Проверить подключение WebSocket
sudo netstat -tulpn | grep 8088

# Проверить логи бота на ошибки подключения
sudo journalctl -u novofon-bot | grep -i ari
```

#### Проблема: Звонки не проходят
```bash
# Включить детальное логирование
sudo asterisk -rvvv

# Проверить SIP трафик
sudo tcpdump -i any -n port 5060
```

---

### 6. Быстрая настройка (скрипт)

Создай файл `setup_asterisk.sh` и выполни:

```bash
#!/bin/bash
# Замени эти значения на свои
SIP_LOGIN="твой_sip_логин"
SIP_PASSWORD="твой_sip_пароль"
PUBLIC_IP="109.73.192.126"
CALLER_ID="+79581114585"

# Обновить pjsip.conf
sudo sed -i "s/YOUR_SIP_LOGIN_HERE/$SIP_LOGIN/g" /etc/asterisk/pjsip.conf
sudo sed -i "s/YOUR_SIP_PASSWORD_HERE/$SIP_PASSWORD/g" /etc/asterisk/pjsip.conf
sudo sed -i "s/YOUR_PUBLIC_IP_HERE/$PUBLIC_IP/g" /etc/asterisk/pjsip.conf

# Обновить extensions.conf
sudo sed -i "s/YOUR_CALLER_ID_HERE/$CALLER_ID/g" /etc/asterisk/extensions.conf

# Перезагрузить
sudo systemctl restart asterisk
sudo asterisk -rx "pjsip reload"
sudo asterisk -rx "dialplan reload"
```

---

## Готово! 🎉

Теперь бот может:
- ✅ Звонить тебе (исходящие звонки)
- ✅ Отвечать на твои звонки (входящие звонки)
- ✅ Вести диалог через ElevenLabs ASR/TTS

