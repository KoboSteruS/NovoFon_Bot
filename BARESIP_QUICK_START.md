# 🚀 Быстрый старт с Baresip

## Что нужно сделать на сервере

### 1. Установка baresip

```bash
sudo apt update
sudo apt install -y baresip baresip-mod-websocket baresip-mod-httpreq
```

### 2. Настройка конфигов

```bash
# Создать директорию
mkdir -p ~/.baresip

# Скопировать конфиги из проекта
cp baresip_configs/config ~/.baresip/config
cp baresip_configs/accounts ~/.baresip/accounts

# Установить права
chmod 644 ~/.baresip/config
chmod 644 ~/.baresip/accounts
```

### 3. Создать systemd сервис

Создай файл `/etc/systemd/system/baresip.service`:

```ini
[Unit]
Description=Baresip SIP Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/baresip
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=baresip

[Install]
WantedBy=multi-user.target
```

Запуск:

```bash
sudo systemctl daemon-reload
sudo systemctl enable baresip
sudo systemctl start baresip
```

### 4. Обновить конфиги Asterisk

#### `/etc/asterisk/sip.conf`

Убедись что есть peer для baresip:

```ini
;=============== BARESIP PEER (для TTS) ===============

[voicebot]
type=peer
host=127.0.0.1
port=5060
context=from-voicebot
canreinvite=no
qualify=no
dtmfmode=rfc2833
allow=ulaw
allow=alaw
disallow=all
nat=no
```

#### `/etc/asterisk/extensions.conf`

В контексте `[from-novofon]` должно быть:

```ini
[from-novofon]
exten => _X.,1,NoOp(=== Incoming call from NovoFon ===)
 same => n,NoOp(CallerID: ${CALLERID(num)})
 same => n,NoOp(Destination: ${EXTEN})
 same => n,Set(CHANNEL(language)=ru)
 same => n,Dial(SIP/voicebot,60)
 same => n,Hangup()
```

### 5. Перезагрузить Asterisk

```bash
sudo asterisk -rx "module reload"
# или
sudo systemctl restart asterisk
```

### 6. Перезапустить бота

```bash
sudo systemctl restart novofon-bot
```

## ✅ Проверка

### Проверка baresip

```bash
# Статус
sudo systemctl status baresip

# Логи
sudo journalctl -u baresip -f

# WebSocket порт
netstat -tlnp | grep 8000
```

### Проверка подключения

В логах бота должно быть:

```
✅ Baresip client connected successfully
```

### Тестовый звонок

```bash
# Из Asterisk CLI
sudo asterisk -rvvv
originate SIP/voicebot extension 200@test
```

## 📝 Что изменилось

1. **Убрали ARI Playback** - больше не используем файлы `.ulaw` и `sound:`
2. **Добавили baresip** - теперь RTP идет напрямую через baresip WebSocket
3. **Asterisk → baresip → Python → ElevenLabs → Python → baresip → Asterisk**

## 🔧 Структура звонка

```
Входящий звонок от NovoFon
    ↓
Asterisk (sip.conf: from-novofon)
    ↓
Dial(SIP/voicebot)
    ↓
Baresip (принимает звонок)
    ↓
WebSocket событие → Python бот
    ↓
Python принимает звонок через baresip API
    ↓
RTP аудио → ElevenLabs ASR
    ↓
Текст → ElevenLabs TTS
    ↓
PCMU аудио → baresip через WebSocket
    ↓
Baresip отправляет RTP обратно в Asterisk
    ↓
Абонент слышит голос бота
```

## 🐛 Проблемы?

Смотри полную инструкцию: `docs/BARESIP_SETUP.md`

