# Миграция с chan_sip на PJSIP

## Изменения в конфигурации

### 1. Asterisk Extensions (extensions.conf)

**Было (chan_sip):**
```ini
[from-novofon]
exten => _X.,1,Stasis(novofon_bot)
```

**Стало (PJSIP):**
```ini
[incoming-novofon]
exten => _X.,1,NoOp(Incoming call to AI bot)
 same => n,Answer()
 same => n,Stasis(elevenbot)
 same => n,Hangup()
```

### 2. Asterisk ARI Application Name

**Было:** `novofon_bot`  
**Стало:** `elevenbot`

**Обновлено в коде:**
- `app/config.py`: `asterisk_ari_app_name = "elevenbot"`

### 3. PJSIP Configuration

**Endpoint:** `novofon-trunk`  
**AOR:** `novofon-aor`  
**Transport:** `transport-udp`

**Важно:** `direct_media=no` в endpoint (уже установлено)

### 4. Формат каналов

**chan_sip:**
- Канал: `SIP/novofon-ip-00000000`
- Snoop: `Snoop/SIP/novofon-ip-00000000-00000000`

**PJSIP:**
- Канал: `PJSIP/novofon-trunk-00000001`
- Snoop: `PJSIP/novofon-trunk-00000001;2` или `Snoop/PJSIP/...`

## Изменения в коде

### 1. Обновлено название приложения

```python
# app/config.py
asterisk_ari_app_name: str = "elevenbot"  # Было: "novofon_bot"
```

### 2. Улучшена обработка snoop каналов

Код теперь правильно определяет snoop каналы для обоих типов:
- PJSIP: `PJSIP/endpoint-XXXXX;Y`
- chan_sip: `Snoop/SIP/...`

### 3. Улучшено сопоставление media channels

Добавлена логика для автоматического сопоставления snoop каналов с оригинальными каналами по паттерну имени.

## Проверка работы

### 1. Проверьте подключение к ARI

```bash
curl -u asterisk_ari_user:62015326495 http://localhost:8088/ari/asterisk/info
```

### 2. Проверьте WebSocket подключение

В логах должно быть:
```
✅ ARI WebSocket connected successfully
Listening for events on app: elevenbot
```

### 3. Проверьте обработку звонков

При входящем звонке в логах должно быть:
```
=== STASIS START ===
Channel ID: PJSIP/novofon-trunk-00000001
```

### 4. Проверьте snoop channel

После создания snoop должно быть:
```
✅ Snoop channel started: PJSIP/novofon-trunk-00000001;2
📋 Snoop configuration: spy=both, whisper=none
```

### 5. Проверьте RTP capture

При разговоре должны появляться события:
```
🔊 ChannelMediaReceived event received!
✅ Sent X bytes of pcmu audio to processor
```

## Важные настройки PJSIP

### 1. direct_media=no

**КРИТИЧНО:** Должно быть `direct_media=no` в endpoint, иначе RTP пойдет напрямую и snoop не сможет его захватить.

```ini
[novofon-trunk]
type=endpoint
direct_media=no  ; ← ВАЖНО!
```

### 2. canreinvite=no (для chan_sip)

Если вы все еще используете chan_sip где-то, убедитесь что:
```ini
[606147]
type=peer
canreinvite=no  ; ← ВАЖНО!
```

## Отладка

### Проверка PJSIP endpoint

```bash
asterisk -rx "pjsip show endpoint novofon-trunk"
```

### Проверка каналов

```bash
asterisk -rx "channel show"
```

### Проверка RTP

```bash
asterisk -rvvv
# Включите RTP debug:
rtp set debug on
```

### Проверка ARI событий

В логах бота ищите:
- `StasisStart` - канал вошел в Stasis
- `ChannelMediaReceived` - получен RTP пакет
- `PlaybackStarted` - началось воспроизведение TTS
- `PlaybackFinished` - завершилось воспроизведение TTS

## Известные проблемы

### 1. ChannelMediaReceived не приходит

**Причины:**
- `direct_media=yes` в endpoint
- `canreinvite=yes` в chan_sip peer
- Snoop создан с `spy="in"` вместо `spy="both"`
- Версия Asterisk не поддерживает ChannelMediaReceived для snoop

**Решение:**
1. Проверьте `direct_media=no` / `canreinvite=no`
2. Проверьте `spy="both"` в snoop_channel()
3. Обновите Asterisk до версии 18+

### 2. Snoop channel не создается

**Причины:**
- Неправильное название приложения в Stasis
- Канал не в Stasis
- Проблемы с правами ARI пользователя

**Решение:**
1. Проверьте, что в extensions.conf указано `Stasis(elevenbot)`
2. Проверьте, что канал действительно входит в Stasis (смотрите логи)
3. Проверьте права ARI пользователя

## Миграция обратно на chan_sip

Если нужно вернуться на chan_sip:

1. Измените `asterisk_ari_app_name` обратно на `novofon_bot`
2. Обновите extensions.conf:
   ```ini
   [from-novofon]
   exten => _X.,1,Stasis(novofon_bot)
   ```
3. Используйте `sip.conf` вместо `pjsip.conf`
4. Перезагрузите Asterisk

