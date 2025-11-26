# Установка и настройка PJSIP с WebSocket для NovoFon Bot

## 📋 Описание

PJSIP используется как SIP+RTP клиент для обработки звонков через WebSocket. Это более стабильное решение по сравнению с baresip, с полной поддержкой WebSocket транспорта.

## 🔧 Установка

### Автоматическая установка

Используйте готовый скрипт:

```bash
chmod +x PJSIP_INSTALL.sh
sudo ./PJSIP_INSTALL.sh
```

Скрипт выполнит:
1. Установку всех зависимостей
2. Скачивание и компиляцию PJSIP 2.14.1 с WebSocket
3. Настройку Asterisk для WebSocket
4. Проверку установки

### Ручная установка

#### Часть 1. Установка зависимостей

```bash
apt update
apt install -y \
  build-essential \
  git \
  libssl-dev \
  libsrtp2-dev \
  libasound2-dev \
  libavcodec-dev \
  libavutil-dev \
  libswresample-dev \
  libavformat-dev \
  libopus-dev \
  python3 python3-pip
```

#### Часть 2. Скачивание PJSIP 2.14.1

```bash
cd /usr/local/src
git clone https://github.com/pjsip/pjproject.git
cd pjproject
git checkout 2.14.1
```

#### Часть 3. Конфигурация с WebSocket

```bash
cat > user.mak <<EOF
PJ_CONFIGURE_OPTS = --enable-shared
CFLAGS += -DPJ_HAS_SSL_SOCK=1
CFLAGS += -DPJMEDIA_HAS_WEBRTC_AEC=0
CFLAGS += -DPJSIP_HAS_WS_TRANSPORT=1
EOF

./configure --enable-shared
```

#### Часть 4. Компиляция

```bash
make dep
make -j$(nproc)
make install
ldconfig
```

#### Часть 5. Проверка

```bash
pjsua --version
pjsua --help | grep websocket
```

Должно быть:
```
--websocket ws://0.0.0.0:5066
--websocket wss://0.0.0.0:5067
```

## 🔌 Настройка Asterisk

### 1. HTTP/WebSocket сервер

Отредактируйте `/etc/asterisk/http.conf`:

```ini
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088

; WebSocket support
wsenabled=yes
wssenabled=yes
```

### 2. PJSIP WebSocket транспорт

Отредактируйте `/etc/asterisk/pjsip.conf`, добавьте:

```ini
; WebSocket transport (WS)
[transport-ws]
type=transport
protocol=ws
bind=0.0.0.0

; WebSocket Secure transport (WSS) - опционально
[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0
cert_file=/etc/asterisk/keys/asterisk.pem
priv_key_file=/etc/asterisk/keys/asterisk.key
```

### 3. Перезапуск Asterisk

```bash
sudo systemctl restart asterisk
```

### 4. Проверка

```bash
# Проверка порта 8088
sudo netstat -tulpn | grep 8088

# Проверка WebSocket транспорта
sudo asterisk -rx "pjsip show transports"
```

Должно быть:
```
Transport: ws, protocol: ws, bind: 0.0.0.0
```

## 🚀 Запуск pjsua клиента

### Вариант 1: Systemd сервис (рекомендуется)

```bash
chmod +x PJSIP_SERVICE.sh
sudo ./PJSIP_SERVICE.sh
sudo systemctl daemon-reload
sudo systemctl enable pjsua
sudo systemctl start pjsua
```

### Вариант 2: Ручной запуск

#### WebSocket (WS):

```bash
pjsua --log-level=5 \
  --websocket ws://0.0.0.0:5066 \
  sip:voicebot@asterisk.local
```

#### WebSocket Secure (WSS):

```bash
pjsua --log-level=5 \
  --websocket wss://0.0.0.0:5067 \
  --use-tls \
  sip:voicebot@asterisk.local
```

## ✅ Проверка работы

### 1. Проверка pjsua

```bash
# Статус сервиса
sudo systemctl status pjsua

# Логи
sudo journalctl -u pjsua -f
```

### 2. Проверка WebSocket подключения

```bash
# Проверка порта
netstat -tlnp | grep 5066

# Внешний клиент
wscat -c ws://server:8088/ws
```

### 3. Проверка в Asterisk

```bash
# Список транспортов
sudo asterisk -rx "pjsip show transports"

# Список endpoints
sudo asterisk -rx "pjsip show endpoints"

# Список регистраций
sudo asterisk -rx "pjsip show registrations"
```

## 🐛 Устранение проблем

### PJSIP не компилируется

```bash
# Проверьте зависимости
dpkg -l | grep -E "libssl|libsrtp|libavcodec"

# Очистите и пересоберите
cd /usr/local/src/pjproject
make clean
make distclean
./configure --enable-shared
make dep && make -j$(nproc) && make install
```

### WebSocket транспорт не работает

```bash
# Проверьте http.conf
grep -i websocket /etc/asterisk/http.conf

# Проверьте pjsip.conf
grep -i "transport-ws" /etc/asterisk/pjsip.conf

# Перезагрузите модули
sudo asterisk -rx "module reload http"
sudo asterisk -rx "module reload res_pjsip"
```

### pjsua не подключается

```bash
# Проверьте логи pjsua
sudo journalctl -u pjsua -f

# Проверьте логи Asterisk
sudo tail -f /var/log/asterisk/full | grep -i websocket

# Проверьте сеть
netstat -tulpn | grep -E "5066|8088"
```

### Порт 8088 не открыт

```bash
# Проверьте http.conf
cat /etc/asterisk/http.conf | grep -E "enabled|bindport|wsenabled"

# Перезапустите Asterisk
sudo systemctl restart asterisk

# Проверьте firewall
sudo ufw status
sudo ufw allow 8088/tcp
```

## 📝 Интеграция с Python ботом

PJSIP может управляться через WebSocket API. Пример подключения:

```python
import asyncio
import websockets
import json

async def connect_pjsip():
    uri = "ws://127.0.0.1:5066"
    async with websockets.connect(uri) as websocket:
        # Отправка команд pjsua
        await websocket.send(json.dumps({
            "command": "answer",
            "call_id": "..."
        }))
        
        # Получение событий
        async for message in websocket:
            event = json.loads(message)
            print(f"Event: {event}")

asyncio.run(connect_pjsip())
```

## 🔄 Обновление

Для обновления PJSIP:

```bash
cd /usr/local/src/pjproject
git fetch origin
git checkout 2.14.1
git reset --hard 2.14.1
make clean
./configure --enable-shared
make dep && make -j$(nproc) && make install
ldconfig
sudo systemctl restart pjsua
```

## 📚 Дополнительные ресурсы

- [PJSIP Documentation](https://www.pjsip.org/)
- [PJSIP WebSocket Transport](https://www.pjsip.org/pjsip/docs/html/group__PJSIP__TRANSPORT__WS.htm)
- [Asterisk PJSIP Configuration](https://wiki.asterisk.org/wiki/display/AST/Configuring+res_pjsip)

