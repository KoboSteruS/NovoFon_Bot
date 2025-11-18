#!/bin/bash
# Исправление проблемы с squid в dpkg

echo "🔧 Исправление проблемы с squid..."

# Вариант 1: Пропускаем squid (если он не критичен)
echo "Вариант 1: Пропускаем squid..."
sudo dpkg --configure --pending || true

# Если не помогло - принудительно завершаем squid
echo "Вариант 2: Принудительное завершение squid..."
sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confold || true

# Очищаем состояние squid
echo "Очищаем состояние squid..."
sudo dpkg --remove --force-remove-reinstreq squid 2>/dev/null || true

# Проверяем
echo "Проверяем dpkg..."
sudo dpkg --configure -a

echo "✅ Готово! Теперь можно запустить install.sh"

