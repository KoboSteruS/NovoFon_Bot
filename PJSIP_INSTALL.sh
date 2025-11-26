#!/bin/bash
# Скрипт установки и настройки PJSIP 2.14.1 с WebSocket для NovoFon Bot

set -e

echo "=========================================="
echo "Установка PJSIP 2.14.1 с WebSocket"
echo "=========================================="

# Часть 0. Очистка старой установки и проблемных репозиториев
echo "🧹 Часть 0: Предварительная очистка..."

# 0.1 Отключаем устаревший baresip репозиторий (если остался)
BARESIP_REPO="/etc/apt/sources.list.d/baresip.list"
if [ -f "$BARESIP_REPO" ]; then
    echo "⚠️  Найден устаревший baresip репозиторий. Отключаем..."
    if grep -q "^deb " "$BARESIP_REPO"; then
        sed -i 's/^deb /# deb /' "$BARESIP_REPO"
    fi
    echo "✅ Репозиторий baresip отключен: $BARESIP_REPO"
fi

# 0.2 Останавливаем старый сервис pjsua (если он есть)
if systemctl list-unit-files | grep -q "^pjsua.service" 2>/dev/null; then
    echo "⏹️  Останавливаем существующий pjsua.service..."
    systemctl stop pjsua 2>/dev/null || true
fi

# 0.3 Удаляем старые бинарники и библиотеки PJSIP
echo "🗑️  Удаляем старые бинарники/библиотеки PJSIP..."
rm -rf /usr/local/src/pjproject
rm -f /usr/local/lib/libpj*.so*
rm -f /usr/local/lib/libpjnath*.so*
rm -f /usr/local/lib/libpjmedia*.so*
rm -f /usr/local/lib/libpjsip*.so*
rm -f /usr/local/lib/libpjsua*.so*
rm -f /usr/local/lib/libpj*.a
rm -f /usr/local/lib/libpjsua*.a
rm -rf /usr/local/include/pjlib*
rm -rf /usr/local/include/pjnath
rm -rf /usr/local/include/pjmedia
rm -rf /usr/local/include/pjsip
rm -rf /usr/local/include/pjsua*
ldconfig
echo "✅ Очистка завершена"

# Часть 1. Установка зависимостей
echo "📦 Часть 1: Установка зависимостей..."
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

echo "✅ Зависимости установлены"

# Часть 2. Скачивание PJSIP 2.14.1
echo "📥 Часть 2: Скачивание PJSIP 2.14.1..."
mkdir -p /usr/local/src
cd /usr/local/src
git clone https://github.com/pjsip/pjproject.git
cd pjproject
git checkout 2.14.1

echo "✅ PJSIP 2.14.1 скачан"

# Часть 3. Конфигурация PJSIP с WebSocket
echo "🔧 Часть 3: Конфигурация PJSIP с WebSocket..."
cat > user.mak <<'EOF'
PJ_CONFIGURE_OPTS = --enable-shared --enable-ssl --enable-transport-websocket --with-openssl
CFLAGS += -DPJ_HAS_SSL_SOCK=1
CFLAGS += -DPJMEDIA_HAS_WEBRTC_AEC=0
CFLAGS += -DPJSIP_HAS_WS_TRANSPORT=1
EOF

echo "✅ user.mak создан"

# Конфигурируем с правильными флагами для WebSocket
echo "🔧 Конфигурирование PJSIP с WebSocket поддержкой..."
export CFLAGS="$CFLAGS -DPJSIP_HAS_WS_TRANSPORT=1"
export LDFLAGS="$LDFLAGS -lssl -lcrypto"
export LIBS="$LIBS -lssl -lcrypto"
if ./configure --enable-shared --enable-ssl --enable-ext-sound --enable-transport-websocket --with-openssl; then
    echo "✅ Конфигурация завершена"
    
    # Проверяем, что WebSocket транспорт включен
    if grep -q "PJSIP_HAS_WS_TRANSPORT" config.log 2>/dev/null || grep -q "transport.*websocket" config.log 2>/dev/null; then
        echo "✅ WebSocket транспорт включен в конфигурации"
    else
        echo "⚠️  Предупреждение: WebSocket транспорт может быть не включен"
        echo "Проверяем config.log..."
        grep -i "websocket\|ws_transport" config.log 2>/dev/null | head -5 || echo "Нет упоминаний WebSocket в config.log"
    fi
else
    echo "❌ Ошибка конфигурации PJSIP!"
    echo "Проверьте зависимости и логи выше"
    exit 1
fi

# Часть 4. Компиляция PJSIP
echo "🔨 Часть 4: Компиляция PJSIP (это может занять несколько минут)..."
echo "Используется $(nproc) ядер процессора"
if make dep && make -j$(nproc) && make install; then
    ldconfig
    echo "✅ PJSIP скомпилирован и установлен"
    
    # Копируем pjsua в /usr/local/bin для доступа из PATH
    echo "📦 Установка pjsua в /usr/local/bin..."
    PJSUA_BIN=$(find pjsip-apps/bin -name "pjsua-*" -type f 2>/dev/null | head -1)
    if [ -n "$PJSUA_BIN" ] && [ -f "$PJSUA_BIN" ]; then
        sudo cp "$PJSUA_BIN" /usr/local/bin/pjsua
        sudo chmod 755 /usr/local/bin/pjsua
        echo "✅ pjsua установлен в /usr/local/bin/pjsua"
    else
        echo "⚠️  pjsua не найден в pjsip-apps/bin, проверяем вручную..."
        find pjsip-apps/bin -name "*pjsua*" 2>/dev/null || echo "pjsua не найден"
    fi
else
    echo "❌ Ошибка компиляции PJSIP!"
    echo "Проверьте логи выше для деталей"
    exit 1
fi

# Опционально: Сборка Python bindings (pjsua2)
# Установите BUILD_PYTHON_BINDINGS=yes для сборки Python bindings
if [ "${BUILD_PYTHON_BINDINGS:-no}" = "yes" ]; then
    echo "🐍 Сборка Python bindings (pjsua2)..."
    if ! command -v swig &> /dev/null; then
        echo "📦 Установка swig для Python bindings..."
        apt install -y swig python3-dev
    fi

    cd pjsip-apps/src/swig
    if make python 2>/dev/null; then
        echo "✅ pjsua2 библиотеки собраны"

        # Определяем директорию site-packages
        PYTHON_SITE_DIR=$(python3 - <<'PY'
import site, sys
paths = site.getsitepackages() or [site.getusersitepackages()]
print(paths[0] if paths else "/usr/local/lib/python3/dist-packages")
PY
)

        echo "📁 Копируем pjsua2 в ${PYTHON_SITE_DIR}..."
        PJSUA2_SO=$(find build -name "_pjsua2*.so" | head -n 1)
        if [ -z "$PJSUA2_SO" ]; then
            echo "❌ Не найден скомпилированный _pjsua2*.so"
        else
            cp "$PJSUA2_SO" "${PYTHON_SITE_DIR}/"
            cp pjsua2.py "${PYTHON_SITE_DIR}/"
            echo "✅ Python модуль pjsua2 установлен"
            echo "  from pjsua2 import *"
        fi
    else
        echo "⚠️  Не удалось собрать pjsua2 (см. логи выше)"
    fi
    cd /usr/local/src/pjproject

    echo "ℹ️  Модуль pjsua (Python 2) больше не поддерживается и не устанавливается"
else
    echo "⏭️  Пропускаем сборку Python bindings (установите BUILD_PYTHON_BINDINGS=yes для включения)"
fi

# Часть 5. Проверка WebSocket транспорта
echo "🔍 Часть 5: Проверка WebSocket транспорта..."
echo "=========================================="

WS_STATUS="UNKNOWN"
WS_ISSUES=""

if command -v pjsua &> /dev/null; then
    echo "✅ pjsua найден: $(which pjsua)"
    
    # Проверка 1: Опции в --help
    if pjsua --help 2>&1 | grep -qE "websocket"; then
        echo "✅ WebSocket опции найдены в справке pjsua"
        WS_STATUS="OK"
        echo "Доступные опции WebSocket:"
        pjsua --help 2>&1 | grep -i "websocket" || true
    else
        echo "⚠️  WebSocket опции НЕ найдены в справке pjsua"
        WS_ISSUES="${WS_ISSUES}• WebSocket опции отсутствуют в --help\n"
        
        # Проверка 2: Строки в бинарнике
        echo "Проверяем наличие WebSocket в собранном бинарнике..."
        if strings /usr/local/bin/pjsua 2>/dev/null | grep -qi websocket; then
            echo "✅ WebSocket строки найдены в бинарнике"
            WS_STATUS="PARTIAL"
            echo "Найденные строки:"
            strings /usr/local/bin/pjsua 2>/dev/null | grep -i websocket | head -5
            WS_ISSUES="${WS_ISSUES}• WebSocket скомпилирован, но опции не показываются в --help\n"
        else
            echo "❌ WebSocket строки НЕ найдены в бинарнике"
            WS_STATUS="FAILED"
            WS_ISSUES="${WS_ISSUES}• WebSocket НЕ скомпилирован в pjsua\n"
            
            # Проверка 3: config.log и проверка компиляции pjsua
            echo "Проверяем config.log на наличие WebSocket транспорта..."
            if [ -f "/usr/local/src/pjproject/config.log" ]; then
                WS_IN_CONFIG=$(grep -iE "websocket|ws_transport|PJSIP_HAS_WS" /usr/local/src/pjproject/config.log 2>/dev/null | wc -l)
                if [ "$WS_IN_CONFIG" -gt 0 ]; then
                    echo "⚠️  WebSocket упоминается в config.log ($WS_IN_CONFIG раз)"
                    echo "Фрагменты из config.log:"
                    grep -iE "websocket|ws_transport|PJSIP_HAS_WS" /usr/local/src/pjproject/config.log 2>/dev/null | head -5
                    
                    # Проверяем, был ли WebSocket включен при компиляции pjsua
                    echo "Проверяем, был ли WebSocket включен в pjsua при компиляции..."
                    if grep -q "enable-transport-websocket" /usr/local/src/pjproject/config.log 2>/dev/null; then
                        echo "✅ Флаг --enable-transport-websocket найден в config.log"
                        # Проверяем, был ли он успешно применен
                        if grep -qE "transport.*websocket.*yes|PJSIP_HAS_WS_TRANSPORT.*1" /usr/local/src/pjproject/config.log 2>/dev/null; then
                            echo "✅ WebSocket транспорт был включен при конфигурации"
                            WS_ISSUES="${WS_ISSUES}• WebSocket включен в config, но не скомпилирован в pjsua (возможно, ошибка компиляции)\n"
                        else
                            echo "⚠️  WebSocket флаг есть, но транспорт не был включен"
                            WS_ISSUES="${WS_ISSUES}• WebSocket флаг указан, но транспорт не активирован\n"
                        fi
                    else
                        WS_ISSUES="${WS_ISSUES}• WebSocket упоминается в config.log, но флаг не найден\n"
                    fi
                else
                    echo "❌ WebSocket НЕ упоминается в config.log"
                    WS_ISSUES="${WS_ISSUES}• WebSocket не был включен при конфигурации\n"
                fi
            else
                echo "⚠️  config.log не найден"
                WS_ISSUES="${WS_ISSUES}• config.log недоступен для проверки\n"
            fi
            
            # Проверка 4: Проверяем исходники pjsua на наличие WebSocket кода
            echo "Проверяем исходники pjsua на наличие WebSocket..."
            if [ -f "/usr/local/src/pjproject/pjsip-apps/src/pjsua/pjsua_app.c" ]; then
                if grep -qiE "websocket|ws_transport" /usr/local/src/pjproject/pjsip-apps/src/pjsua/pjsua_app.c 2>/dev/null; then
                    echo "✅ WebSocket код найден в исходниках pjsua"
                else
                    echo "⚠️  WebSocket код НЕ найден в исходниках pjsua"
                    WS_ISSUES="${WS_ISSUES}• WebSocket код отсутствует в исходниках pjsua\n"
                fi
            fi
            
            # Проверка 5: Флаги компиляции в user.mak
            echo "Проверяем флаги компиляции в user.mak..."
            if [ -f "/usr/local/src/pjproject/user.mak" ]; then
                if grep -q "enable-transport-websocket" /usr/local/src/pjproject/user.mak 2>/dev/null; then
                    echo "✅ Флаг --enable-transport-websocket найден в user.mak"
                else
                    echo "❌ Флаг --enable-transport-websocket НЕ найден в user.mak"
                    WS_ISSUES="${WS_ISSUES}• Флаг --enable-transport-websocket отсутствует в user.mak\n"
                fi
            fi
        fi
    fi
    
    # Проверка версии
    echo "Версия pjsua:"
    pjsua --version 2>&1 | head -1 || true
    
else
    echo "❌ pjsua не найден в PATH"
    WS_STATUS="FAILED"
    WS_ISSUES="${WS_ISSUES}• pjsua не установлен в системе\n"
    echo "Проверяем наличие в исходниках..."
    PJSUA_FOUND=$(find /usr/local/src/pjproject/pjsip-apps/bin -name "*pjsua*" 2>/dev/null | head -1)
    if [ -n "$PJSUA_FOUND" ]; then
        echo "⚠️  pjsua найден в исходниках: $PJSUA_FOUND"
        echo "💡 Скопируйте вручную: sudo cp $PJSUA_FOUND /usr/local/bin/pjsua"
        WS_ISSUES="${WS_ISSUES}• pjsua найден в исходниках, но не в PATH\n"
    else
        echo "❌ pjsua не найден нигде"
        WS_ISSUES="${WS_ISSUES}• pjsua не был собран\n"
    fi
fi

# Итоговый отчет
echo ""
echo "=========================================="
echo "📊 ИТОГОВЫЙ СТАТУС WebSocket (Этап 5):"
echo "=========================================="

# Проверяем, используется ли ARI/Stasis (для этого проекта)
ARI_USED=false
if [ -f "/etc/asterisk/ari.conf" ] || asterisk -rx "module show like res_ari" 2>/dev/null | grep -q "res_ari"; then
    ARI_USED=true
fi

case "$WS_STATUS" in
    "OK")
        echo "✅ WebSocket транспорт в pjsua: РАБОТАЕТ"
        echo "   Все проверки пройдены успешно"
        ;;
    "PARTIAL")
        echo "⚠️  WebSocket транспорт в pjsua: ЧАСТИЧНО РАБОТАЕТ"
        echo "   WebSocket скомпилирован, но опции не показываются"
        echo "   Возможно, это особенность версии 2.14.1"
        ;;
    "FAILED")
        echo "❌ WebSocket транспорт в pjsua: НЕ РАБОТАЕТ"
        echo ""
        echo "🔍 Обнаруженные проблемы:"
        echo -e "$WS_ISSUES"
        
        if [ "$ARI_USED" = true ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━скрипт, чтобы он правильно интерпретировал результаты для ARI/Stasis сценария.
</think>
Обновляю скрипт: для ARI/Stasis отсутствие WebSocket в pjsua не критично. Добавляю проверку и соответствующие сообщения.
<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>
read_file

# Часть 6. Настройка Asterisk для WebSocket
echo "🔧 Часть 6: Настройка Asterisk для WebSocket..."

# Проверяем существование http.conf
if [ -f "/etc/asterisk/http.conf" ]; then
    echo "📝 Обновление /etc/asterisk/http.conf..."
    
    # Создаем backup
    cp /etc/asterisk/http.conf /etc/asterisk/http.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Обновляем http.conf
    if ! grep -q "^enabled=yes" /etc/asterisk/http.conf; then
        sed -i 's/^enabled=.*/enabled=yes/' /etc/asterisk/http.conf || echo "enabled=yes" >> /etc/asterisk/http.conf
    fi
    
    if ! grep -q "^bindaddr=0.0.0.0" /etc/asterisk/http.conf; then
        sed -i 's/^bindaddr=.*/bindaddr=0.0.0.0/' /etc/asterisk/http.conf || echo "bindaddr=0.0.0.0" >> /etc/asterisk/http.conf
    fi
    
    if ! grep -q "^bindport=8088" /etc/asterisk/http.conf; then
        sed -i 's/^bindport=.*/bindport=8088/' /etc/asterisk/http.conf || echo "bindport=8088" >> /etc/asterisk/http.conf
    fi
    
    # Включаем WebSocket (правильный синтаксис)
    if ! grep -q "^websocket_enabled=yes" /etc/asterisk/http.conf; then
        echo "" >> /etc/asterisk/http.conf
        echo "; WebSocket support" >> /etc/asterisk/http.conf
        echo "websocket_enabled=yes" >> /etc/asterisk/http.conf
    fi
    
    echo "✅ http.conf обновлен"
else
    echo "📝 Создание /etc/asterisk/http.conf..."
    cat > /etc/asterisk/http.conf <<'EOF'
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088

; WebSocket support
websocket_enabled=yes
EOF
    chown asterisk:asterisk /etc/asterisk/http.conf
    chmod 644 /etc/asterisk/http.conf
    echo "✅ http.conf создан"
fi

# Обновляем pjsip.conf для WebSocket транспорта
echo "📝 Обновление /etc/asterisk/pjsip.conf..."
if [ -f "/etc/asterisk/pjsip.conf" ]; then
    # Создаем backup
    cp /etc/asterisk/pjsip.conf /etc/asterisk/pjsip.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Проверяем наличие transport-ws
    if ! grep -q "^\[transport-ws\]" /etc/asterisk/pjsip.conf; then
        echo "" >> /etc/asterisk/pjsip.conf
        echo "; WebSocket transport (WS)" >> /etc/asterisk/pjsip.conf
        echo "[transport-ws]" >> /etc/asterisk/pjsip.conf
        echo "type=transport" >> /etc/asterisk/pjsip.conf
        echo "protocol=ws" >> /etc/asterisk/pjsip.conf
        echo "bind=0.0.0.0" >> /etc/asterisk/pjsip.conf
        echo "" >> /etc/asterisk/pjsip.conf
    fi
    
    # Проверяем наличие transport-wss (опционально, если есть сертификаты)
    if ! grep -q "^\[transport-wss\]" /etc/asterisk/pjsip.conf; then
        echo "; WebSocket Secure transport (WSS) - опционально" >> /etc/asterisk/pjsip.conf
        echo "; [transport-wss]" >> /etc/asterisk/pjsip.conf
        echo "; type=transport" >> /etc/asterisk/pjsip.conf
        echo "; protocol=wss" >> /etc/asterisk/pjsip.conf
        echo "; bind=0.0.0.0" >> /etc/asterisk/pjsip.conf
        echo "; cert_file=/etc/asterisk/keys/asterisk.pem" >> /etc/asterisk/pjsip.conf
        echo "; priv_key_file=/etc/asterisk/keys/asterisk.key" >> /etc/asterisk/pjsip.conf
        echo "" >> /etc/asterisk/pjsip.conf
    fi
    
    echo "✅ pjsip.conf обновлен"
else
    echo "⚠️  /etc/asterisk/pjsip.conf не найден, создаем базовую конфигурацию..."
    cat > /etc/asterisk/pjsip.conf <<'EOF'
[global]
; Global PJSIP settings

; WebSocket transport (WS)
[transport-ws]
type=transport
protocol=ws
bind=0.0.0.0

; WebSocket Secure transport (WSS) - опционально
; [transport-wss]
; type=transport
; protocol=wss
; bind=0.0.0.0
; cert_file=/etc/asterisk/keys/asterisk.pem
; priv_key_file=/etc/asterisk/keys/asterisk.key
EOF
    chown asterisk:asterisk /etc/asterisk/pjsip.conf
    chmod 644 /etc/asterisk/pjsip.conf
    echo "✅ pjsip.conf создан"
fi

# Обновляем modules.conf для загрузки WebSocket модулей
echo "📝 Обновление /etc/asterisk/modules.conf..."
if [ -f "/etc/asterisk/modules.conf" ]; then
    # Создаем backup
    cp /etc/asterisk/modules.conf /etc/asterisk/modules.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Проверяем наличие WebSocket модулей
    if ! grep -q "^load => res_http_websocket.so" /etc/asterisk/modules.conf; then
        echo "" >> /etc/asterisk/modules.conf
        echo "; WebSocket modules for PJSIP" >> /etc/asterisk/modules.conf
        echo "load => res_http_websocket.so" >> /etc/asterisk/modules.conf
    fi
    
    if ! grep -q "^load => res_pjsip_transport_websocket.so" /etc/asterisk/modules.conf; then
        echo "load => res_pjsip_transport_websocket.so" >> /etc/asterisk/modules.conf
    fi
    
    echo "✅ modules.conf обновлен"
else
    echo "⚠️  /etc/asterisk/modules.conf не найден, создаем базовую конфигурацию..."
    cat > /etc/asterisk/modules.conf <<'EOF'
; Asterisk modules configuration
; WebSocket modules for PJSIP
load => res_http_websocket.so
load => res_pjsip_transport_websocket.so
EOF
    chown asterisk:asterisk /etc/asterisk/modules.conf
    chmod 644 /etc/asterisk/modules.conf
    echo "✅ modules.conf создан"
fi

# Часть 7. Перезапуск Asterisk
echo "🔄 Часть 7: Перезапуск Asterisk..."
if systemctl is-active --quiet asterisk; then
    systemctl restart asterisk
    echo "✅ Asterisk перезапущен"
    sleep 2
else
    echo "⚠️  Asterisk не запущен, запускаем..."
    systemctl start asterisk || echo "⚠️  Не удалось запустить Asterisk"
fi

# Часть 8. Проверка установки
echo "🔍 Часть 8: Проверка установки..."

# Проверка pjsua
if command -v pjsua &> /dev/null; then
    echo "✅ pjsua установлен: $(pjsua --version 2>&1 | head -1)"
else
    echo "❌ pjsua не найден!"
fi

# Проверка порта 8088
echo "🔍 Проверка WebSocket порта 8088..."
if netstat -tulpn 2>/dev/null | grep -q ":8088"; then
    echo "✅ Asterisk слушает на порту 8088"
    netstat -tulpn | grep 8088
else
    echo "⚠️  Порт 8088 не открыт"
    echo "Проверяем логи Asterisk..."
    journalctl -u asterisk -n 20 --no-pager | tail -10 || true
fi

# Проверка WebSocket транспорта в Asterisk
echo "🔍 Проверка WebSocket транспорта в Asterisk..."
sleep 2  # Даем время Asterisk загрузить модули

# Сначала проверяем, есть ли модули res_pjsip
PJSIP_MODULES_OUTPUT=$(asterisk -rx "module show like pjsip" 2>/dev/null)
PJSIP_MODULES=$(echo "$PJSIP_MODULES_OUTPUT" | grep -c "res_pjsip" 2>/dev/null || echo "0")
# Убираем пробелы и переносы строк, оставляем только первое число
PJSIP_MODULES=$(echo "$PJSIP_MODULES" | tr -d '[:space:]' | head -1)
# Если пусто или не число, ставим 0
if [ -z "$PJSIP_MODULES" ] || ! [ "$PJSIP_MODULES" -eq "$PJSIP_MODULES" ] 2>/dev/null; then
    PJSIP_MODULES=0
fi
if [ "$PJSIP_MODULES" -gt 0 ] 2>/dev/null; then
    echo "✅ Модули res_pjsip загружены ($PJSIP_MODULES модулей)"
    if asterisk -rx "pjsip show transports" 2>/dev/null | grep -qE "ws|wss|websocket"; then
        echo "✅ WebSocket транспорт зарегистрирован в Asterisk"
        asterisk -rx "pjsip show transports" 2>/dev/null | grep -E "ws|wss|websocket" || true
    else
        echo "⚠️  WebSocket транспорт не найден в Asterisk PJSIP"
        echo "Проверяем все транспорты:"
        asterisk -rx "pjsip show transports" 2>/dev/null || true
        echo ""
        echo "💡 Убедитесь, что в /etc/asterisk/pjsip.conf есть секция [transport-ws]"
    fi
else
    echo "⚠️  Модули res_pjsip не загружены в Asterisk"
    echo "Это означает, что Asterisk собран без PJSIP поддержки или модули не включены"
    echo "Проверяем загруженные WebSocket модули:"
    asterisk -rx "module show like websocket" 2>/dev/null | grep -i websocket || true
    echo ""
    echo "💡 Для использования PJSIP WebSocket транспорта нужно:"
    echo "   1. Пересобрать Asterisk с поддержкой res_pjsip"
    echo "   2. Или установить пакет asterisk-pjsip (если доступен)"
    echo "   3. Убедиться, что в /etc/asterisk/modules.conf загружены модули res_pjsip"
fi

# Проверка загруженных WebSocket модулей
echo "🔍 Проверка загруженных WebSocket модулей..."
if asterisk -rx "module show like websocket" 2>/dev/null | grep -q "websocket"; then
    echo "✅ WebSocket модули загружены"
    asterisk -rx "module show like websocket" 2>/dev/null | grep -i websocket || true
else
    echo "⚠️  WebSocket модули не загружены"
    echo "Попробуйте перезагрузить модули:"
    echo "  sudo asterisk -rx 'module reload res_http_websocket.so'"
    echo "  sudo asterisk -rx 'module reload res_pjsip_transport_websocket.so'"
fi

echo ""
echo "=========================================="
echo "✅ PJSIP установлен и настроен!"
echo "=========================================="
echo ""
echo "Проверка работы:"
echo "  pjsua --version"
echo "  pjsua --help | grep websocket"
echo "  sudo netstat -tulpn | grep 8088"
echo "  sudo asterisk -rx 'pjsip show transports'"
echo ""
echo "Тестирование WebSocket:"
echo "  pjsua --log-level=5 --websocket ws://127.0.0.1:5066 sip:test@localhost"
echo ""
echo "Проверка внешним клиентом:"
echo "  wscat -c ws://server:8088/ws"
echo ""
echo "Логи Asterisk:"
echo "  sudo journalctl -u asterisk -f"
echo ""
echo "Для сборки Python bindings при следующей установке:"
echo "  BUILD_PYTHON_BINDINGS=yes ./PJSIP_INSTALL.sh"
echo ""

