#!/bin/bash
# Скрипт для разблокировки apt/dpkg

set -e

echo "=========================================="
echo "🔧 Разблокировка apt/dpkg"
echo "=========================================="
echo ""

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    error "Запустите с sudo: sudo bash fix_apt_lock.sh"
    exit 1
fi

info "Шаг 1: Проверяем процессы apt..."
ps aux | grep -E "apt|dpkg" | grep -v grep || info "Активных процессов apt/dpkg не найдено"

info "Шаг 2: Ищем процессы, держащие блокировки..."
LOCKED_PIDS=$(lsof /var/lib/dpkg/lock-frontend 2>/dev/null | grep -v COMMAND | awk '{print $2}' | sort -u)
if [ -n "$LOCKED_PIDS" ]; then
    warn "Найдены процессы, держащие блокировку: $LOCKED_PIDS"
    for PID in $LOCKED_PIDS; do
        info "Проверяем процесс $PID..."
        ps -p $PID -o pid,cmd --no-headers || warn "Процесс $PID уже не существует"
    done
else
    info "Процессы не держат блокировку напрямую"
fi

info "Шаг 3: Убиваем зависшие процессы apt/dpkg..."
pkill -9 apt || info "Процессы apt не найдены"
pkill -9 dpkg || info "Процессы dpkg не найдены"
sleep 2

info "Шаг 4: Удаляем блокировочные файлы..."
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/dpkg/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/apt/lists/lock
info "✅ Блокировочные файлы удалены"

info "Шаг 5: Восстанавливаем состояние dpkg..."
dpkg --configure -a || warn "dpkg --configure завершился с ошибкой (возможно, нормально)"

info "Шаг 6: Проверяем целостность пакетов..."
apt-get check || warn "apt-get check обнаружил проблемы"

info "Шаг 7: Очищаем кеш apt..."
apt-get clean
apt-get autoclean

info "Шаг 8: Тестируем apt..."
if apt-get update -qq; then
    info "✅ apt работает нормально!"
    echo ""
    info "Теперь можно запустить установку:"
    info "  sudo bash install.sh"
else
    error "❌ apt всё ещё не работает. Возможно, нужна перезагрузка."
    exit 1
fi

echo ""
info "✅ Разблокировка завершена!"

