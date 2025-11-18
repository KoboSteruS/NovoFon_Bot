#!/bin/bash
# Быстрая разблокировка apt - выполни на сервере

echo "🔧 Разблокировка apt..."

# Убиваем процессы
sudo pkill -9 apt 2>/dev/null
sudo pkill -9 dpkg 2>/dev/null
sleep 1

# Удаляем блокировки
sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/apt/lists/lock

# Восстанавливаем
sudo dpkg --configure -a

# Проверяем
echo "Проверяем apt..."
if sudo apt-get update -qq 2>&1 | head -5; then
    echo "✅ apt разблокирован!"
else
    echo "⚠️  Возможны проблемы, но попробуй запустить установку"
fi

