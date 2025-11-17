# Asterisk Configuration Files

## 📁 Файлы конфигурации

Эти файлы нужно скопировать в `/etc/asterisk/` на сервере с Asterisk.

### ari.conf
- Настройка ARI интерфейса
- **ВАЖНО**: Измените пароль в секции `[novofon_bot]`

### http.conf
- Настройка HTTP сервера для ARI
- Порт 8088 для ARI REST API

### pjsip.conf
- Настройка SIP транка к NovoFon
- **ВАЖНО**: Замените все `YOUR_*_HERE` на ваши данные

### extensions.conf
- Dialplan (сценарии обработки звонков)
- Входящие звонки попадают в context `from-novofon`
- Исходящие через context `from-internal`

---

## 🔧 Установка

### 1. Скопируйте файлы на сервер с Asterisk

```bash
# Сделайте резервные копии оригиналов
sudo cp /etc/asterisk/ari.conf /etc/asterisk/ari.conf.backup
sudo cp /etc/asterisk/http.conf /etc/asterisk/http.conf.backup
sudo cp /etc/asterisk/pjsip.conf /etc/asterisk/pjsip.conf.backup
sudo cp /etc/asterisk/extensions.conf /etc/asterisk/extensions.conf.backup

# Скопируйте новые файлы
sudo cp ari.conf /etc/asterisk/
sudo cp http.conf /etc/asterisk/
sudo cp pjsip.conf /etc/asterisk/
sudo cp extensions.conf /etc/asterisk/

# Установите правильные права
sudo chown asterisk:asterisk /etc/asterisk/*.conf
sudo chmod 640 /etc/asterisk/*.conf
```

### 2. Измените значения на ваши данные

В файле `pjsip.conf`:
- `YOUR_PUBLIC_IP_HERE` - ваш публичный IP адрес
- `YOUR_SIP_LOGIN_HERE` - логин SIP от NovoFon
- `YOUR_SIP_PASSWORD_HERE` - пароль SIP от NovoFon
- `IP_ADDRESS_OF_NOVOFON_HERE` - IP адрес SIP сервера NovoFon

В файле `ari.conf`:
- Измените пароль в секции `[novofon_bot]`

В файле `extensions.conf`:
- `YOUR_CALLER_ID_HERE` - ваш номер телефона (Caller ID)

### 3. Перезапустите Asterisk

```bash
sudo asterisk -rx "core reload"
# Или полный рестарт:
sudo systemctl restart asterisk
```

---

## ✅ Проверка

### 1. Проверьте PJSIP endpoints

```bash
sudo asterisk -rx "pjsip show endpoints"
```

Должен показать endpoint `novofon` в статусе `Unavail` или `Avail`.

### 2. Проверьте ARI

```bash
curl -u novofon_bot:your_password http://localhost:8088/ari/asterisk/info
```

Должен вернуть JSON с информацией об Asterisk.

### 3. Проверьте dialplan

```bash
sudo asterisk -rx "dialplan show from-novofon"
```

Должен показать extension'ы из context `from-novofon`.

---

## 🔐 Обновите .env в Python боте

После настройки Asterisk, обновите `.env` файл в проекте Python:

```env
ASTERISK_ARI_URL=http://your_asterisk_server:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=your_ari_password_here
ASTERISK_ARI_APP_NAME=novofon_bot
```

Если Asterisk на том же сервере что и Python бот:
```env
ASTERISK_ARI_URL=http://localhost:8088/ari
```

---

## 🆘 Troubleshooting

### PJSIP не подключается к NovoFon

```bash
# Включите PJSIP логирование
sudo asterisk -rx "pjsip set logger on"

# Смотрите логи
sudo tail -f /var/log/asterisk/full
```

### ARI не отвечает

```bash
# Проверьте HTTP сервер
sudo asterisk -rx "http show status"

# Проверьте ARI приложения
sudo asterisk -rx "ari show apps"
```

### Звонки не проходят

```bash
# Смотрите dialplan execution
sudo asterisk -rx "core set verbose 5"
sudo tail -f /var/log/asterisk/full
```

---

## 📚 Полезные команды Asterisk CLI

```bash
# Подключиться к CLI
sudo asterisk -rvvv

# В CLI:
pjsip show endpoints        # Список SIP endpoints
pjsip show registrations    # Регистрации
core show channels          # Активные звонки
ari show apps               # ARI приложения
dialplan show               # Весь dialplan
core reload                 # Перезагрузить конфигурацию
```

