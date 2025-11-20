# 📋 Файлы для копирования на сервер

## Что нужно скопировать на сервер

### 1. Конфиги baresip

```bash
# На сервере создать директорию
mkdir -p ~/.baresip

# Скопировать файлы
cp baresip_configs/config ~/.baresip/config
cp baresip_configs/accounts ~/.baresip/accounts

# Установить права
chmod 644 ~/.baresip/config
chmod 644 ~/.baresip/accounts
```

### 2. Обновить конфиги Asterisk

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

В контексте `[from-novofon]` изменить на:

```ini
[from-novofon]
exten => _X.,1,NoOp(=== Incoming call from NovoFon ===)
 same => n,NoOp(CallerID: ${CALLERID(num)})
 same => n,NoOp(Destination: ${EXTEN})
 same => n,Set(CHANNEL(language)=ru)
 same => n,Dial(SIP/voicebot,60)
 same => n,Hangup()

exten => s,1,NoOp(=== Unknown incoming call ===)
 same => n,Dial(SIP/voicebot,60)
 same => n,Hangup()
```

### 3. Systemd сервис для baresip

Создать файл `/etc/systemd/system/baresip.service`:

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

## 📝 Содержимое файлов конфигов

### `~/.baresip/config`

```
# Baresip configuration for NovoFon Bot
# Place this file in ~/.baresip/config

# Audio driver (null для сервера без звуковой карты)
audio_driver		null
audio_player		null
audio_source		null

# SIP settings
sip_listen		0.0.0.0:5060

# WebSocket module for Python control
module			websock.so
websock_listen		0.0.0.0:8000

# HTTP request module (optional, for status)
module			httpreq.so

# Audio codecs (только PCMU для совместимости с Asterisk)
audio_codecs		pcmu

# RTP settings
rtp_tos			184
rtp_port_min		10000
rtp_port_max		20000

# Logging
log_level		info
```

### `~/.baresip/accounts`

```
# Baresip SIP accounts
# Place this file in ~/.baresip/accounts
# Format: <sip:user@host:port>;auth_pass=password;regint=interval

# Local SIP account for Asterisk to call
# Asterisk will call: SIP:voicebot@127.0.0.1:5060
# regint=0 означает что регистрация не нужна (IP-auth)
<sip:voicebot@127.0.0.1:5060>;auth_pass=voicebot123;regint=0
```

## ✅ После копирования

1. Установить baresip:
   ```bash
   sudo apt install -y baresip baresip-mod-websocket baresip-mod-httpreq
   ```

2. Запустить baresip:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable baresip
   sudo systemctl start baresip
   ```

3. Перезагрузить Asterisk:
   ```bash
   sudo asterisk -rx "module reload"
   ```

4. Перезапустить бота:
   ```bash
   sudo systemctl restart novofon-bot
   ```

## 🔍 Проверка

```bash
# Проверка baresip
sudo systemctl status baresip
sudo journalctl -u baresip -f

# Проверка WebSocket
netstat -tlnp | grep 8000

# Проверка бота
sudo journalctl -u novofon-bot -f | grep -i baresip
```

Должно быть: `✅ Baresip client connected successfully`

