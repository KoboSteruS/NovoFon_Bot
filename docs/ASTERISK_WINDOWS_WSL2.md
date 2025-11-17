# 🪟 Установка Asterisk на Windows через WSL2

## Способ 1: WSL2 (РЕКОМЕНДУЕТСЯ) ⭐

### Шаг 1: Установка WSL2

**Откройте PowerShell от имени администратора** и выполните:

```powershell
# Установить WSL2 с Ubuntu (одна команда!)
wsl --install

# Или если нужна конкретная версия Ubuntu:
wsl --install -d Ubuntu-22.04
```

**После установки:**
1. Перезагрузите компьютер
2. При первом запуске Ubuntu создайте пользователя и пароль
3. Готово! Теперь у вас есть Linux внутри Windows

---

### Шаг 2: Запустите Ubuntu

Найдите в Пуске **"Ubuntu"** или **"Ubuntu 22.04"** и запустите.

Откроется терминал Linux!

---

### Шаг 3: Установите Asterisk в Ubuntu (WSL2)

В терминале Ubuntu выполните:

```bash
# Обновите систему
sudo apt update && sudo apt upgrade -y

# Установите Asterisk
sudo apt install -y asterisk

# Запустите Asterisk
sudo systemctl start asterisk
sudo systemctl enable asterisk

# Проверьте версию
sudo asterisk -rx "core show version"
```

Должно показать версию Asterisk (например: `Asterisk 18.x.x`).

---

### Шаг 4: Настройте конфигурационные файлы

```bash
# Перейдите в папку проекта (Windows диски доступны через /mnt/)
cd /mnt/f/Projects/NovoFon_Bot

# Скопируйте конфиги
sudo cp asterisk_configs/ari.conf /etc/asterisk/
sudo cp asterisk_configs/http.conf /etc/asterisk/
sudo cp asterisk_configs/pjsip.conf /etc/asterisk/
sudo cp asterisk_configs/extensions.conf /etc/asterisk/

# Откройте pjsip.conf для редактирования
sudo nano /etc/asterisk/pjsip.conf
```

**В pjsip.conf замените:**
- `YOUR_SIP_LOGIN_HERE` → ваш SIP логин от NovoFon
- `YOUR_SIP_PASSWORD_HERE` → ваш SIP пароль от NovoFon
- `YOUR_PUBLIC_IP_HERE` → ваш публичный IP (узнайте командой `curl ifconfig.me`)

**Сохраните:** Ctrl+O, Enter, Ctrl+X

```bash
# Также настройте ARI пароль
sudo nano /etc/asterisk/ari.conf
```

Замените `asterisk_ari_password_change_me` на свой пароль.

**Сохраните:** Ctrl+O, Enter, Ctrl+X

---

### Шаг 5: Перезапустите Asterisk

```bash
sudo systemctl restart asterisk

# Проверьте статус
sudo systemctl status asterisk

# Проверьте SIP endpoints
sudo asterisk -rx "pjsip show endpoints"
```

---

### Шаг 6: Обновите .env в Windows

Откройте файл `.env` в проекте (через Блокнот или VSCode) и добавьте:

```env
# Asterisk ARI (localhost работает, т.к. WSL2 пробрасывает порты)
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=novofon_bot
ASTERISK_ARI_PASSWORD=ваш_пароль_из_ari.conf
ASTERISK_ARI_APP_NAME=novofon_bot
```

---

### Шаг 7: Запустите Python бота (в Windows)

**В обычной командной строке Windows** (НЕ в Ubuntu):

```cmd
cd F:\Projects\NovoFon_Bot
venv\Scripts\activate
python run_dev.py
```

Asterisk работает в WSL2, а Python бот в Windows - они соединятся через localhost!

---

## ✅ Проверка работы

### 1. Asterisk работает в WSL2?

В Ubuntu терминале:
```bash
sudo systemctl status asterisk
```

### 2. Python бот подключился к Asterisk?

В логах Python бота должно быть:
```
INFO | Asterisk ARI connected successfully
```

### 3. SIP подключён к NovoFon?

В Ubuntu:
```bash
sudo asterisk -rx "pjsip show endpoints"
```

Endpoint `novofon` должен быть `Avail` или `Unavail` (но не `Not in use`).

---

## 🔧 Полезные команды WSL2

### Управление WSL2 (из PowerShell в Windows):

```powershell
# Список установленных дистрибутивов
wsl --list --verbose

# Запустить WSL2
wsl

# Остановить WSL2
wsl --shutdown

# Перезапустить конкретный дистрибутив
wsl --terminate Ubuntu-22.04
```

### Доступ к файлам:

**Из Windows:**
- Откройте Проводник → адресная строка: `\\wsl$\Ubuntu-22.04\`
- Или в VSCode: Remote - WSL расширение

**Из Ubuntu (WSL2):**
- Windows диски доступны в `/mnt/c/`, `/mnt/f/` и т.д.
- Пример: `/mnt/f/Projects/NovoFon_Bot`

---

## 🆘 Troubleshooting

### WSL2 не устанавливается

**Ошибка:** "WSL 2 requires an update to its kernel component"

**Решение:**
1. Скачайте обновление: https://aka.ms/wsl2kernel
2. Установите
3. Повторите `wsl --install`

---

### Asterisk не запускается в WSL2

```bash
# Проверьте логи
sudo tail -f /var/log/asterisk/messages

# Или запустите в debug режиме
sudo asterisk -cvvvvv
```

---

### Python бот не подключается к Asterisk

**Проблема:** Порт 8088 не доступен из Windows

**Решение 1:** WSL2 обычно пробрасывает порты автоматически. Проверьте:
```powershell
# В PowerShell (Windows)
netstat -an | findstr 8088
```

**Решение 2:** Узнайте IP адрес WSL2 и используйте его:
```bash
# В Ubuntu (WSL2)
hostname -I
```

Полученный IP используйте в `.env`:
```env
ASTERISK_ARI_URL=http://172.x.x.x:8088/ari
```

---

### Firewall блокирует

**Windows Defender Firewall** может блокировать порты.

**Решение:** Добавьте правило для порта 8088:
```powershell
# В PowerShell от админа
New-NetFirewallRule -DisplayName "Asterisk ARI" -Direction Inbound -LocalPort 8088 -Protocol TCP -Action Allow
```

---

## 💡 Преимущества WSL2

✅ Быстрая установка (одна команда)
✅ Нативная производительность Linux
✅ Доступ к файлам Windows из Linux и наоборот
✅ Не нужна виртуальная машина
✅ Встроено в Windows 10/11
✅ Автоматический проброс портов

---

## 🎯 Следующие шаги

После успешной установки:

1. ✅ WSL2 установлен
2. ✅ Ubuntu запущен
3. ✅ Asterisk работает
4. ✅ Конфиги настроены
5. ✅ Python бот подключён к Asterisk
6. ⏭️ Переходим к Этапу 4 (ElevenLabs)

---

## 📚 Дополнительные ресурсы

- [Официальная документация WSL2](https://docs.microsoft.com/en-us/windows/wsl/)
- [VSCode + WSL2](https://code.visualstudio.com/docs/remote/wsl)
- [Docker Desktop + WSL2](https://docs.docker.com/desktop/windows/wsl/)

