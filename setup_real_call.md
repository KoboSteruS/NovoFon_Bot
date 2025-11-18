# 📞 Настройка реального звонка через NovoFon

## Проблема

`application Playback` - это внутренняя обработка, звонок не уходит в NovoFon.

## Решение: Используй Dial()

### 1. Добавь extension для исходящих звонков

```bash
sudo nano /etc/asterisk/extensions.conf
```

Добавь в конец файла:

```ini
[outgoing]
; Реальный звонок через NovoFon на внешний номер
exten => _X.,1,NoOp(=== Outgoing call to ${EXTEN} via NovoFon ===)
 same => n,Set(CALLERID(num)=+79581114585)
 same => n,Set(CALLERID(name)=NovoFon Bot)
 same => n,Dial(PJSIP/${EXTEN}@novofon,30)
 same => n,Hangup()
```

### 2. Перезагрузи dialplan

```bash
sudo asterisk -rx "dialplan reload"
```

### 3. Сделай реальный звонок

```bash
sudo asterisk -rx "channel originate Local/79991234567@outgoing application Playback hello-world"
```

Где `79991234567` - номер БЕЗ + (можно свой мобильный для теста).

### 4. Или через консоль Asterisk

```bash
sudo asterisk -rvvv
```

В консоли:

```bash
channel originate Local/79991234567@outgoing application Playback hello-world
```

---

## Проверка перед звонком

### 1. Проверь конфигурацию pjsip.conf

```bash
sudo cat /etc/asterisk/pjsip.conf | grep -A 2 "\[novofon\]"
```

Должно быть:
- `username = ТВОЙ_ЛОГИН`
- `password = ТВОЙ_ПАРОЛЬ`
- `contact = sip:sip.novofon.ru`

### 2. Проверь endpoint

```bash
sudo asterisk -rx "pjsip show endpoints" | grep novofon
```

### 3. Проверь SIP трафик (в отдельном терминале)

```bash
sudo tcpdump -i any -n port 5060 -v
```

Должны быть пакеты к `sip.novofon.ru` когда делаешь звонок.

---

## Что должно произойти

1. Asterisk создаст канал `Local/79991234567@outgoing`
2. Dialplan вызовет `Dial(PJSIP/79991234567@novofon)`
3. Asterisk отправит INVITE на `sip.novofon.ru:5060`
4. NovoFon получит запрос с твоего IP (109.73.192.126)
5. NovoFon дозвонится до указанного номера
6. Ты получишь звонок на телефон
7. NovoFon зафиксирует звонок и активирует транк

---

## Если не работает

### Проверь логи в реальном времени:

```bash
sudo tail -f /var/log/asterisk/full
```

Ищи ошибки типа:
- "No matching endpoint found"
- "Authentication failed"
- "No route to destination"

### Проверь, что в pjsip.conf есть логин и пароль:

```bash
sudo grep -A 1 "username\|password" /etc/asterisk/pjsip.conf | grep novofon
```

Если их нет - нужно получить от NovoFon или создать транк в личном кабинете.

