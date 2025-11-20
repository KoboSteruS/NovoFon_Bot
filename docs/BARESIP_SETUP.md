# Установка и настройка Baresip

## 📋 Описание

Baresip используется как SIP+RTP клиент для обработки звонков. Asterisk перенаправляет входящие звонки в baresip, а Python управляет baresip через WebSocket API для обработки RTP аудио.

## 🔧 Установка

### 1. Установка baresip и модулей

```bash
sudo apt update
sudo apt install -y baresip baresip-mod-websocket baresip-mod-httpreq
```

Проверка установки:

```bash
baresip -v
```

### 2. Создание директории конфигурации

```bash
mkdir -p ~/.baresip
```

### 3. Копирование конфигурационных файлов

```bash
# Скопируй файлы из проекта
cp baresip_configs/config ~/.baresip/config
cp baresip_configs/accounts ~/.baresip/accounts

# Установи права
chmod 644 ~/.baresip/config
chmod 644 ~/.baresip/accounts
```

### 4. Настройка конфигурации

#### `~/.baresip/config`

Основные параметры:
- `websock_listen 0.0.0.0:8000` - WebSocket API для Python
- `audio_driver null` - null драйвер (сервер без звуковой карты)
- `audio_codecs pcmu` - только PCMU для совместимости

#### `~/.baresip/accounts`

Учетная запись для приема звонков от Asterisk:
```
<sip:voicebot@127.0.0.1:5060>;auth_pass=voicebot123;regint=0
```

### 5. Запуск baresip

#### Вариант 1: Systemd сервис (рекомендуется)

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
sudo systemctl status baresip
```

#### Вариант 2: Ручной запуск

```bash
baresip
```

## 🔌 Настройка Asterisk

### 1. Обновление sip.conf

Убедись что в `/etc/asterisk/sip.conf` есть peer для baresip:

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

### 2. Обновление extensions.conf

В контексте `[from-novofon]` измени на:

```ini
[from-novofon]
exten => _X.,1,NoOp(=== Incoming call from NovoFon ===)
 same => n,NoOp(CallerID: ${CALLERID(num)})
 same => n,NoOp(Destination: ${EXTEN})
 same => n,Set(CHANNEL(language)=ru)
 same => n,Dial(SIP/voicebot,60)
 same => n,Hangup()
```

### 3. Перезагрузка Asterisk

```bash
sudo asterisk -rx "module reload"
# или
sudo systemctl restart asterisk
```

## ✅ Проверка работы

### 1. Проверка baresip

```bash
# Проверь что baresip запущен
sudo systemctl status baresip

# Проверь логи
sudo journalctl -u baresip -f

# Проверь WebSocket порт
netstat -tlnp | grep 8000
```

### 2. Проверка подключения Python к baresip

В логах бота должно быть:

```
✅ Baresip client connected successfully
```

### 3. Тестовый звонок

```bash
# Из Asterisk CLI
sudo asterisk -rvvv
originate SIP/voicebot extension 200@test
```

В логах бота должно появиться:

```
📞 Incoming call: <call_id>
✅ Call established: <call_id>
```

## 🐛 Устранение проблем

### Baresip не запускается

```bash
# Проверь конфигурацию
baresip -v

# Проверь права на файлы
ls -la ~/.baresip/

# Проверь что порт 5060 свободен
netstat -tlnp | grep 5060
```

### WebSocket не работает

```bash
# Проверь что модуль websock загружен
baresip -m | grep websock

# Проверь порт 8000
netstat -tlnp | grep 8000

# Проверь логи baresip
sudo journalctl -u baresip -f
```

### Asterisk не может дозвониться до baresip

```bash
# Проверь что baresip слушает на 127.0.0.1:5060
netstat -tlnp | grep 5060

# Проверь SIP peers в Asterisk
sudo asterisk -rx "sip show peers"
sudo asterisk -rx "sip show peer voicebot"

# Проверь логи Asterisk
sudo tail -f /var/log/asterisk/full
```

### RTP не проходит

```bash
# Проверь что порты RTP открыты (10000-20000)
netstat -tlnp | grep -E "10000|15000|20000"

# Проверь firewall
sudo ufw status
sudo ufw allow 10000:20000/udp
```

## 📝 Логирование

Логи baresip:

```bash
sudo journalctl -u baresip -f
```

Логи Python бота:

```bash
sudo journalctl -u novofon-bot -f
```

Логи Asterisk:

```bash
sudo tail -f /var/log/asterisk/full
```

## 🔄 Перезапуск после изменений

```bash
# Перезапуск baresip
sudo systemctl restart baresip

# Перезапуск бота
sudo systemctl restart novofon-bot

# Перезагрузка Asterisk конфигов
sudo asterisk -rx "module reload"
```

