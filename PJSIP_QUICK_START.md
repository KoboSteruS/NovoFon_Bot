# 🚀 Быстрый старт с PJSIP

## Установка (один скрипт)

```bash
chmod +x PJSIP_INSTALL.sh
sudo ./PJSIP_INSTALL.sh
```

Скрипт автоматически:
- ✅ Установит все зависимости
- ✅ Соберет PJSIP 2.14.1 с WebSocket
- ✅ Настроит Asterisk для WebSocket
- ✅ Проверит установку

## Создание systemd сервиса для pjsua

```bash
chmod +x PJSIP_SERVICE.sh
sudo ./PJSIP_SERVICE.sh
sudo systemctl daemon-reload
sudo systemctl enable pjsua
sudo systemctl start pjsua
```

## Проверка

```bash
# Проверка pjsua
pjsua --version
pjsua --help | grep websocket

# Проверка Asterisk WebSocket
sudo netstat -tulpn | grep 8088
sudo asterisk -rx "pjsip show transports"

# Проверка сервиса
sudo systemctl status pjsua
sudo journalctl -u pjsua -f
```

## Что дальше?

1. **Настройте Asterisk** - скопируйте обновленные конфиги:
   ```bash
   sudo cp asterisk_configs/http.conf /etc/asterisk/http.conf
   sudo cp asterisk_configs/pjsip.conf /etc/asterisk/pjsip.conf
   sudo cp asterisk_configs/modules.conf /etc/asterisk/modules.conf
   sudo systemctl restart asterisk
   ```

2. **Проверьте WebSocket**:
   ```bash
   wscat -c ws://127.0.0.1:8088/ws
   ```

3. **Интегрируйте с Python ботом** - используйте WebSocket API для управления pjsua

## Полная документация

Смотри `docs/PJSIP_SETUP.md` для детальной информации.

