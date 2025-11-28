# Архитектура подключения через Asterisk ARI/Stasis

## Обзор

Бот работает через **Asterisk ARI (Asterisk REST Interface)** и **Stasis**, а НЕ через PJSIP WebSocket клиент.

PJSIP WebSocket был бы нужен только если бы мы использовали `pjsua` как SIP-клиент, но мы используем Asterisk напрямую через ARI.

## Текущая архитектура

```
┌─────────────┐
│   Клиент    │ (звонящий)
│  (SIP/Phone)│
└──────┬──────┘
       │ SIP/RTP
       ▼
┌─────────────────────────────────────┐
│         Asterisk                     │
│  ┌───────────────────────────────┐   │
│  │  Stasis Application           │   │
│  │  (novofon_bot)                 │   │
│  └───────────────────────────────┘   │
│  ┌───────────────────────────────┐   │
│  │  ARI WebSocket Server          │   │
│  │  ws://asterisk:8088/ari/events │   │
│  └───────────────────────────────┘   │
│  ┌───────────────────────────────┐   │
│  │  Snoop Channel (RTP capture)  │   │
│  └───────────────────────────────┘   │
└──────┬───────────────────────────────┘
       │ ARI WebSocket (события)
       │ ARI REST API (команды)
       ▼
┌─────────────────────────────────────┐
│      Python Bot                      │
│  ┌───────────────────────────────┐   │
│  │  AsteriskARIClient             │   │
│  │  - WebSocket для событий       │   │
│  │  - REST API для управления     │   │
│  └───────────────────────────────┘   │
│  ┌───────────────────────────────┐   │
│  │  VoiceProcessor                │   │
│  │  - ASR (ElevenLabs)            │   │
│  │  - TTS (ElevenLabs)            │   │
│  └───────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Компоненты

### 1. Asterisk ARI WebSocket

**Что это:**
- WebSocket сервер встроенный в Asterisk
- Отправляет события в реальном времени (StasisStart, ChannelMediaReceived, etc.)
- Работает через модуль `res_http_websocket.so`

**URL подключения:**
```
ws://asterisk_host:8088/ari/events?app=novofon_bot&api_key=username:password
```

**Настройка в Asterisk:**
```ini
# /etc/asterisk/http.conf
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
websocket_enabled=yes  # ← Важно!

# /etc/asterisk/ari.conf
[general]
enabled = yes
pretty = yes

[novofon_bot]
type = user
read_only = no
password = your_password
```

### 2. Stasis Application

**Что это:**
- Приложение в Asterisk, которое перехватывает звонки
- Настраивается в `extensions.conf` через `Stasis()` dialplan application

**Настройка в Asterisk:**
```ini
# /etc/asterisk/extensions.conf
[from-novofon]
exten => s,1,Stasis(novofon_bot)
exten => s,n,Hangup()
```

**Как работает:**
1. Входящий звонок попадает в контекст `from-novofon`
2. Asterisk вызывает `Stasis(novofon_bot)`
3. Звонок переходит в Stasis application
4. Asterisk отправляет событие `StasisStart` через ARI WebSocket
5. Бот получает событие и начинает обработку

### 3. Snoop Channel (захват RTP)

**Что это:**
- ARI метод для мониторинга RTP потока канала
- Позволяет получать аудио данные в реальном времени

**Как используется:**
```python
# Создаем snoop channel для захвата RTP
snoop_channel = await ari_client.snoop_channel(
    channel_id=channel_id,
    app="novofon_bot",
    spy="both",      # Слушаем входящий и исходящий RTP
    whisper="none"   # Не отправляем аудио обратно
)

# Asterisk отправляет события ChannelMediaReceived
# с аудио данными от snoop channel
```

**Важно:**
- Snoop channel создается **один раз** на звонок
- TTS проигрывается на **оригинальном канале**, НЕ на snoop
- Snoop используется только для захвата входящего аудио (ASR)

### 4. TTS Playback

**Как работает:**
1. Бот получает текст от FSM
2. Отправляет в ElevenLabs TTS
3. Получает PCM16 аудио (16kHz)
4. Сохраняет как `.sln16` файл в `/usr/share/asterisk/sounds/`
5. Проигрывает через ARI `play_media()` на **оригинальном канале**

**Код:**
```python
# voice_processor.py
async def _send_audio_to_asterisk(self, pcm16_data: bytes):
    # Сохраняем как SLIN16 файл
    slin_path = f"/usr/share/asterisk/sounds/{filename}.sln16"
    with open(slin_path, 'wb') as f:
        f.write(pcm16_data)
    
    # Проигрываем на оригинальном канале
    await self.ari_client.play_media(
        channel_id=self.channel_id,  # ← Оригинальный канал, НЕ snoop!
        media=f"sound:{filename}"
    )
```

## Что НЕ нужно

### ❌ PJSIP WebSocket клиент (`pjsua`)

**Почему не нужен:**
- `pjsua` - это SIP-клиент для подключения к Asterisk как SIP peer
- Мы используем Asterisk напрямую через ARI, а не как SIP peer
- PJSIP WebSocket нужен только если бы мы использовали `pjsua` для звонков

**Что работает без PJSIP:**
- ✅ Asterisk ARI WebSocket (встроен в Asterisk)
- ✅ Stasis application
- ✅ Snoop channel для RTP
- ✅ TTS playback через ARI

### ❌ Baresip

**Почему не нужен:**
- Baresip - это альтернативный SIP-клиент
- Мы используем Asterisk ARI напрямую
- Baresip был бы нужен только для обхода Asterisk TTS проблем

## Требования для работы

### 1. Asterisk с ARI

```bash
# Проверка модулей
asterisk -rx "module show like res_ari"
asterisk -rx "module show like res_http_websocket"

# Должны быть загружены:
# res_ari.so
# res_http_websocket.so
```

### 2. Конфигурация Asterisk

**http.conf:**
```ini
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
websocket_enabled=yes
```

**ari.conf:**
```ini
[general]
enabled = yes
pretty = yes

[novofon_bot]
type = user
read_only = no
password = your_password
```

**extensions.conf:**
```ini
[from-novofon]
exten => s,1,Stasis(novofon_bot)
exten => s,n,Hangup()
```

### 3. Python зависимости

```python
# app/services/asterisk_ari.py использует:
import websockets  # для ARI WebSocket
import aiohttp     # для ARI REST API
```

## Поток обработки звонка

```
1. Входящий звонок
   ↓
2. Asterisk: Stasis(novofon_bot)
   ↓
3. ARI WebSocket: StasisStart event
   ↓
4. Бот: _on_stasis_start()
   ├─→ answer_channel()
   ├─→ snoop_channel()  ← Создаем snoop для RTP
   ├─→ create_processor()
   └─→ processor.start()  ← Подключаемся к ElevenLabs ASR
   ↓
5. Snoop channel: ChannelMediaReceived events
   ↓
6. Бот: receive_rtp_audio()
   ├─→ Конвертация PCMU → PCM16
   └─→ Отправка в ElevenLabs ASR
   ↓
7. ElevenLabs ASR: final_transcript
   ↓
8. Бот: _handle_user_speech()
   ├─→ FSM.process_user_input()
   └─→ processor.speak()  ← TTS
   ↓
9. ElevenLabs TTS: PCM16 аудио
   ↓
10. Бот: _send_audio_to_asterisk()
    ├─→ Сохранение .sln16 файла
    └─→ play_media() на оригинальном канале
    ↓
11. Абонент слышит голос бота
```

## Проверка работоспособности

### 1. Проверка ARI подключения

```bash
# В логах бота должно быть:
# ✅ ARI WebSocket connected successfully
# Listening for events on app: novofon_bot
```

### 2. Проверка Stasis

```bash
# В логах Asterisk при звонке:
# NOTICE[xxx]: res_stasis: Starting Stasis application 'novofon_bot'
```

### 3. Проверка Snoop Channel

```bash
# В логах бота при звонке:
# ✅ Snoop channel started: <snoop_id> for channel <channel_id>
```

### 4. Проверка RTP захвата

```bash
# В логах бота должны быть:
# ChannelMediaReceived events от snoop channel
# Sent X bytes of pcmu audio to processor
```

## Проблемы и решения

### Проблема: "No handler registered for StasisStart"

**Причина:** Бот не подключен к ARI WebSocket или не зарегистрировал обработчик

**Решение:**
1. Проверьте `asterisk_ari_url`, `asterisk_ari_username`, `asterisk_ari_password` в настройках
2. Проверьте, что `websocket_enabled=yes` в `http.conf`
3. Проверьте, что модуль `res_http_websocket.so` загружен

### Проблема: "Snoop channel failed"

**Причина:** Asterisk не может создать snoop channel

**Решение:**
1. Проверьте права пользователя ARI (должен быть `read_only = no`)
2. Проверьте, что канал в состоянии, когда можно создать snoop

### Проблема: "No ChannelMediaReceived events"

**Причина:** Snoop channel не получает RTP или не отправляет события

**Решение:**
1. Проверьте, что snoop создан с `spy="both"`
2. Проверьте, что канал установлен (answered)
3. Проверьте, что RTP поток активен

### Проблема: "PlaybackFinished state: failed"

**Причина:** Asterisk не может проиграть файл

**Решение:**
1. Проверьте путь к файлу (`/usr/share/asterisk/sounds/`)
2. Проверьте права на файл (должен быть доступен для пользователя asterisk)
3. Проверьте формат файла (должен быть `.sln16` - raw PCM16, 16kHz, mono)

## Итого

**Что работает:**
- ✅ Asterisk ARI WebSocket (встроен в Asterisk)
- ✅ Stasis application для перехвата звонков
- ✅ Snoop channel для захвата RTP
- ✅ TTS playback через ARI

**Что НЕ нужно:**
- ❌ PJSIP WebSocket клиент (`pjsua`)
- ❌ Baresip
- ❌ Любые внешние SIP-клиенты

**Все работает через стандартный Asterisk ARI/Stasis!**



