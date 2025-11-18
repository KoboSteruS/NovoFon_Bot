# 🔧 Исправление проблемы со звонками

## Проблема

API возвращает успех (`status: "ringing"`), но звонок не доходит до телефона. В SIP-трафике видно много попыток авторизации от NovoFon, но они не проходят.

## Решение

### 1. Обнови код на сервере

```bash
cd ~/NovoFon_Bot
git pull
# Или скопируй исправленный файл app/services/asterisk_call_handler.py
```

### 2. Настрой dialplan для исходящих звонков

```bash
sudo bash fix_outgoing_dialplan.sh
```

Этот скрипт:
- Создаст/обновит секцию `[outgoing]` в `/etc/asterisk/extensions.conf`
- Настроит правильный Caller ID (`+79675558164`)
- Перезагрузит dialplan

### 3. Проверь конфигурацию PJSIP

```bash
sudo asterisk -rx "pjsip show endpoints" | grep novofon
```

Должен быть endpoint `novofon`.

### 4. Проверь dialplan

```bash
sudo asterisk -rx "dialplan show outgoing"
```

Должна быть секция `[outgoing]` с правильным номером.

### 5. Перезапусти бота

```bash
sudo systemctl restart novofon-bot
sudo journalctl -u novofon-bot -f
```

### 6. Проверь логи Asterisk

```bash
sudo tail -f /var/log/asterisk/full | grep -i "outgoing\|novofon\|dial"
```

### 7. Попробуй звонок

```bash
curl -X POST http://109.73.192.126/api/calls/initiate \
  -H "Content-Type: application/json" \
  -d '{"phone": "+79522675444"}'
```

## Что изменилось

1. **Код бота**: Теперь использует `Local/{phone}@outgoing` вместо `PJSIP/{phone}@novofon`
2. **Dialplan**: Добавлена секция `[outgoing]` с `Dial(PJSIP/${EXTEN}@novofon)`
3. **Caller ID**: Установлен правильный Caller ID из конфигурации

## Диагностика

Если звонок всё ещё не работает:

```bash
sudo bash debug_call_issue.sh
```

Этот скрипт покажет:
- Статус Asterisk
- PJSIP endpoints
- ARI приложения
- Последние логи
- Ошибки

## Проверка SIP-трафика

```bash
sudo tcpdump -i any -n port 5060 -v | grep -i "invite\|200\|401\|403"
```

Должны быть:
- `INVITE` от Asterisk к NovoFon
- `200 OK` от NovoFon
- `ACK` от Asterisk

Если видишь `401 Unauthorized` или `403 Forbidden` - проблема с авторизацией в PJSIP.

