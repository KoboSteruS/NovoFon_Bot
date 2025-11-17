# Asterisk + ARI Setup Guide

## 📋 Этап 3: Настройка Asterisk для NovoFon Bot

Asterisk будет обрабатывать:
- SIP соединения с NovoFon
- RTP аудиопотоки
- ARI (Asterisk REST Interface) для управления из Python

---

## 🖥 Установка Asterisk

### Ubuntu/Debian (Production)

```bash
# Обновите систему
sudo apt update
sudo apt upgrade -y

# Установите зависимости
sudo apt install -y build-essential wget libssl-dev libncurses5-dev \
  libnewt-dev libxml2-dev linux-headers-$(uname -r) libsqlite3-dev \
  uuid-dev libjansson-dev libspeex-dev libspeexdsp-dev

# Скачайте Asterisk (последняя LTS версия)
cd /usr/src
sudo wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-20-current.tar.gz
sudo tar xvf asterisk-20-current.tar.gz
cd asterisk-20*/

# Установите необходимые MP3 библиотеки
sudo contrib/scripts/get_mp3_source.sh

# Конфигурация
sudo ./configure --with-jansson-bundled

# Выберите модули (обязательно включить: res_ari, res_http_websocket, res_pjsip)
sudo make menuselect

# Компиляция и установка (займёт 10-20 минут)
sudo make -j$(nproc)
sudo make install
sudo make samples
sudo make config
sudo ldconfig

# Создайте пользователя asterisk
sudo groupadd asterisk
sudo useradd -r -d /var/lib/asterisk -g asterisk asterisk
sudo usermod -aG audio,dialout asterisk
sudo chown -R asterisk:asterisk /etc/asterisk
sudo chown -R asterisk:asterisk /var/{lib,log,spool}/asterisk
sudo chown -R asterisk:asterisk /usr/lib/asterisk

# Настройте запуск от имени asterisk
sudo sed -i 's/#AST_USER="asterisk"/AST_USER="asterisk"/' /etc/default/asterisk
sudo sed -i 's/#AST_GROUP="asterisk"/AST_GROUP="asterisk"/' /etc/default/asterisk

# Запустите Asterisk
sudo systemctl enable asterisk
sudo systemctl start asterisk
sudo systemctl status asterisk
```

---

### Windows (Development)

Для Windows **НЕ РЕКОМЕНДУЕТСЯ** устанавливать Asterisk напрямую. Используйте один из вариантов:

#### Вариант 1: WSL2 (Windows Subsystem for Linux) ⭐ Рекомендуется

```powershell
# 1. Включите WSL2
wsl --install

# 2. Перезагрузите компьютер

# 3. Установите Ubuntu из Microsoft Store

# 4. Откройте Ubuntu и следуйте инструкциям выше для Ubuntu
```

#### Вариант 2: Docker

```bash
# Используйте готовый Docker образ с Asterisk
docker pull andrius/asterisk

# Или создайте свой (Dockerfile будет предоставлен отдельно)
```

#### Вариант 3: Виртуальная машина (VirtualBox/VMware)

Установите Ubuntu в VM и следуйте инструкциям для Ubuntu.

---

## ⚙️ Конфигурация Asterisk

После установки нужно настроить конфигурационные файлы.

### 1. Включить ARI

**Файл:** `/etc/asterisk/ari.conf`

```ini
[general]
enabled = yes
pretty = yes
allowed_origins = *

[novofon_bot]
type = user
read_only = no
password = asterisk_ari_password_here
```

### 2. Настроить HTTP сервер

**Файл:** `/etc/asterisk/http.conf`

```ini
[general]
enabled = yes
bindaddr = 0.0.0.0
bindport = 8088
tlsenable = no
tlsbindaddr = 0.0.0.0:8089
tlscertfile = /etc/asterisk/keys/asterisk.pem
tlsprivatekey = /etc/asterisk/keys/asterisk.key
enablestatic = yes
redirect = / /httpstatus
```

### 3. Настроить PJSIP (SIP транк к NovoFon)

**Файл:** `/etc/asterisk/pjsip.conf`

```ini
[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060

[novofon]
type = endpoint
context = from-novofon
disallow = all
allow = ulaw,alaw
aors = novofon
auth = novofon
direct_media = no
ice_support = yes
force_rport = yes
rewrite_contact = yes

[novofon]
type = aor
contact = sip:novofon_sip_server_here
qualify_frequency = 60

[novofon]
type = auth
auth_type = userpass
username = ваш_sip_логин
password = ваш_sip_пароль

[novofon]
type = identify
endpoint = novofon
match = IP_адрес_NovoFon
```

⚠️ **ВАЖНО:** Получите SIP данные от NovoFon:
- SIP сервер
- SIP логин
- SIP пароль
- IP адрес (для identify)

### 4. Настроить Dialplan

**Файл:** `/etc/asterisk/extensions.conf`

```ini
[general]
static = yes
writeprotect = no

[globals]

[from-novofon]
; Входящие звонки от NovoFon
exten => _X.,1,NoOp(Incoming call from NovoFon: ${CALLERID(num)})
 same => n,Stasis(novofon_bot,incoming,${EXTEN})
 same => n,Hangup()

[from-internal]
; Исходящие звонки через NovoFon
exten => _X.,1,NoOp(Outgoing call to: ${EXTEN})
 same => n,Stasis(novofon_bot,outgoing,${EXTEN})
 same => n,Hangup()
```

### 5. Создать ARI приложение

**Файл:** `/etc/asterisk/stasis.conf`

```ini
[novofon_bot]
type = application
```

---

## 🔄 Перезапуск Asterisk

После изменения конфигурации:

```bash
# Проверка конфигурации
sudo asterisk -rx "core reload"

# Или полный перезапуск
sudo systemctl restart asterisk

# Проверка статуса
sudo asterisk -rx "pjsip show endpoints"
sudo asterisk -rx "ari show apps"
```

---

## 🧪 Проверка установки

### 1. Проверьте, что Asterisk запущен

```bash
sudo systemctl status asterisk
```

### 2. Подключитесь к CLI

```bash
sudo asterisk -rvvv
```

Команды в CLI:
```
core show version        # Версия Asterisk
pjsip show endpoints    # SIP endpoints
ari show apps          # ARI приложения
http show status       # HTTP сервер
```

Выход: `Ctrl+C`

### 3. Проверьте ARI через HTTP

```bash
curl -u novofon_bot:asterisk_ari_password_here http://localhost:8088/ari/applications
```

Должно вернуть JSON с приложением `novofon_bot`.

---

## 🔐 Безопасность

### Firewall (Ubuntu)

```bash
# Разрешите необходимые порты
sudo ufw allow 5060/udp  # SIP
sudo ufw allow 10000:20000/udp  # RTP
sudo ufw allow 8088/tcp  # ARI (только с localhost или trusted IP)
```

### SELinux/AppArmor

Если используете, настройте правила для Asterisk.

---

## 📝 Получение SIP данных от NovoFon

1. Зайдите в личный кабинет NovoFon
2. Раздел **"SIP"** или **"Телефония"**
3. Найдите или создайте **SIP-аккаунт**
4. Запишите:
   - **SIP сервер** (например: `sip.novofon.ru`)
   - **Логин** (например: `1234567`)
   - **Пароль**
   - **IP адрес** для регистрации (узнайте у поддержки)

---

## 🆘 Troubleshooting

### Asterisk не запускается

```bash
# Проверьте логи
sudo tail -f /var/log/asterisk/messages
sudo tail -f /var/log/asterisk/full

# Запустите в режиме отладки
sudo asterisk -cvvvvv
```

### SIP не подключается к NovoFon

```bash
# В Asterisk CLI
pjsip set logger on
pjsip show endpoints
pjsip show aors
```

### ARI не отвечает

```bash
# Проверьте HTTP сервер
http show status

# Проверьте права доступа
ls -la /etc/asterisk/ari.conf
```

---

## 🎯 Следующие шаги

После успешной установки и настройки Asterisk:

1. ✅ Asterisk установлен и запущен
2. ✅ ARI включен и доступен
3. ✅ SIP транк к NovoFon настроен
4. ⏭️ Создать Python клиент для ARI (следующий шаг)
5. ⏭️ Интегрировать с NovoFon Bot

---

## 📚 Полезные ссылки

- [Asterisk Wiki](https://wiki.asterisk.org/)
- [ARI Documentation](https://wiki.asterisk.org/wiki/display/AST/Asterisk+REST+Interface)
- [PJSIP Configuration](https://wiki.asterisk.org/wiki/display/AST/PJSIP+Configuration)
- [NovoFon SIP настройки](https://novofon.com/instructions/sip/)

