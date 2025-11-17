# 🚀 Asterisk Quick Start для NovoFon Bot

## ⚡ Для тех, кто хочет быстро запустить

### Вариант 1: WSL2 на Windows (рекомендуется для dev)

```powershell
# 1. Установите WSL2 (если ещё нет)
wsl --install

# 2. Перезагрузите компьютер

# 3. Откройте Ubuntu и выполните:
```

```bash
# Установка Asterisk (в Ubuntu WSL2)
sudo apt update && sudo apt upgrade -y
sudo apt install -y asterisk

# Запуск
sudo systemctl start asterisk
sudo systemctl enable asterisk

# Проверка
sudo asterisk -rx "core show version"
```

---

### Вариант 2: Ubuntu Server (production)

См. полную документацию: `docs/ASTERISK_SETUP.md`

---

## ⚙️ Быстрая настройка (5 минут)

### 1. Получите SIP данные от NovoFon

Зайдите в личный кабинет NovoFon → **SIP** → запишите:
- SIP сервер (обычно `sip.novofon.ru`)
- Логин
- Пароль

### 2. Настройте конфиги

```bash
# Скопируйте готовые конфиги
sudo cp asterisk_configs/ari.conf /etc/asterisk/
sudo cp asterisk_configs/http.conf /etc/asterisk/
sudo cp asterisk_configs/pjsip.conf /etc/asterisk/
sudo cp asterisk_configs/extensions.conf /etc/asterisk/

# Откройте pjsip.conf и замените значения
sudo nano /etc/asterisk/pjsip.conf
```

**Замените в pjsip.conf:**
- `YOUR_SIP_LOGIN_HERE` → ваш SIP логин
- `YOUR_SIP_PASSWORD_HERE` → ваш SIP пароль
- `YOUR_PUBLIC_IP_HERE` → ваш публичный IP (узнайте: `curl ifconfig.me`)

**Сохраните:** Ctrl+O, Enter, Ctrl+X

### 3. Настройте ARI пароль

```bash
sudo nano /etc/asterisk/ari.conf
```

Замените `asterisk_ari_password_change_me` на свой пароль.

### 4. Перезапустите Asterisk

```bash
sudo systemctl restart asterisk

# Проверка
sudo asterisk -rx "pjsip show endpoints"
```

Должно показать `novofon` endpoint.

### 5. Обновите .env в Python проекте

```env
# В файле .env добавьте/обновите:
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=ваш_пароль_из_ari.conf
ASTERISK_ARI_APP_NAME=novofon_bot
```

Если Asterisk на другом сервере:
```env
ASTERISK_ARI_URL=http://IP_СЕРВЕРА:8088/ari
```

### 6. Запустите Python бота

```bash
python run_dev.py
```

Если всё OK, в логах увидите:
```
INFO | Asterisk ARI connected successfully
```

---

## ✅ Проверка работы

### 1. Asterisk работает?

```bash
sudo systemctl status asterisk
```

Должно быть: `active (running)`

### 2. ARI доступен?

```bash
curl -u novofon_bot:ваш_пароль http://localhost:8088/ari/asterisk/info
```

Должен вернуть JSON с информацией.

### 3. SIP подключён к NovoFon?

```bash
sudo asterisk -rx "pjsip show endpoints"
```

Если `novofon` показывает `Avail` - отлично!
Если `Unavail` - проверьте SIP данные в `pjsip.conf`.

---

## 🆘 Проблемы?

### Asterisk не запускается

```bash
# Смотрите логи
sudo tail -f /var/log/asterisk/messages

# Запустите в debug режиме
sudo asterisk -cvvvvv
```

### SIP не подключается

```bash
# В Asterisk CLI:
sudo asterisk -rvvv

# Команды:
pjsip show endpoints
pjsip set logger on
```

Затем смотрите `/var/log/asterisk/full`

### Python бот не подключается к ARI

Проверьте:
1. Asterisk запущен? `sudo systemctl status asterisk`
2. Порт 8088 открыт? `sudo netstat -tulpn | grep 8088`
3. Правильный пароль в `.env`?
4. Firewall? `sudo ufw allow 8088/tcp`

---

## 📚 Что дальше?

После успешной настройки Asterisk:

✅ **Этап 3 завершён!**

Следующие этапы:
- **Этап 4**: ElevenLabs ASR/TTS для обработки голоса
- **Этап 5**: FSM логика диалога
- **Этап 6**: Очередь обзвона

---

## 💡 Полезные команды

```bash
# Подключиться к Asterisk CLI
sudo asterisk -rvvv

# В CLI:
core show version          # Версия
pjsip show endpoints       # SIP endpoints
core show channels         # Активные звонки
ari show apps              # ARI приложения
core set verbose 5         # Включить подробные логи
```

Выход из CLI: Ctrl+C

---

**Нужна помощь?** См. `docs/ASTERISK_SETUP.md` для подробной документации!

