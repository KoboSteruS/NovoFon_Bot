# NovoFon API Testing Guide

## 🚀 Быстрый старт

### 1. Установка зависимостей

```bash
pip install -r requirements.txt
```

### 2. Настройка `.env`

Убедитесь, что в `.env` указаны:

```env
# NovoFon API
NOVOFON_API_KEY=your_real_api_key_here
NOVOFON_API_URL=https://api.novofon.com
NOVOFON_FROM_NUMBER=+7XXXXXXXXXX

# Database
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/novofon_bot
```

### 3. Запуск сервера

```bash
# Development режим
python run_dev.py

# Или через uvicorn
uvicorn app.main:app --reload
```

Сервер запустится на `http://localhost:8000`

## 📡 API Endpoints

### Health Check

**GET** `/health`

Проверка статуса всех сервисов (БД, NovoFon API)

```bash
curl http://localhost:8000/health
```

Ответ:
```json
{
  "status": "healthy",
  "checks": {
    "database": "healthy",
    "novofon_api": "healthy"
  }
}
```

---

### Инициировать звонок

**POST** `/api/calls/initiate`

```bash
curl -X POST "http://localhost:8000/api/calls/initiate" \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+79991234567"
  }'
```

Ответ (успех):
```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "phone": "+79991234567",
  "status": "ringing",
  "start_time": "2024-11-14T10:30:00",
  "end_time": null,
  "duration": null,
  "scenario_result": null,
  "novofon_call_id": "novofon_call_123",
  "error_message": null
}
```

Ответ (ошибка):
```json
{
  "detail": "Failed to initiate call via NovoFon: Authentication failed"
}
```

---

### Получить информацию о звонке

**GET** `/api/calls/{call_id}`

```bash
curl http://localhost:8000/api/calls/123e4567-e89b-12d3-a456-426614174000
```

---

### Получить сообщения (диалог) звонка

**GET** `/api/calls/{call_id}/messages`

```bash
curl http://localhost:8000/api/calls/123e4567-e89b-12d3-a456-426614174000/messages
```

Ответ:
```json
[
  {
    "id": "msg-uuid-1",
    "call_id": "123e4567-e89b-12d3-a456-426614174000",
    "role": "system",
    "text": "Call initiated to +79991234567",
    "timestamp": "2024-11-14T10:30:00",
    "audio_duration": null
  },
  {
    "id": "msg-uuid-2",
    "call_id": "123e4567-e89b-12d3-a456-426614174000",
    "role": "bot",
    "text": "Здравствуйте! Это тестовый звонок.",
    "timestamp": "2024-11-14T10:30:05",
    "audio_duration": 2.5
  }
]
```

---

### Список звонков

**GET** `/api/calls`

Параметры:
- `status` (optional) - фильтр по статусу
- `phone` (optional) - фильтр по номеру
- `limit` (default: 100) - лимит результатов
- `offset` (default: 0) - смещение для пагинации

```bash
# Все звонки
curl http://localhost:8000/api/calls

# Только завершённые
curl "http://localhost:8000/api/calls?status=completed"

# По конкретному номеру
curl "http://localhost:8000/api/calls?phone=%2B79991234567"

# С пагинацией
curl "http://localhost:8000/api/calls?limit=10&offset=20"
```

---

### Завершить звонок

**POST** `/api/calls/{call_id}/hangup`

```bash
curl -X POST http://localhost:8000/api/calls/123e4567-e89b-12d3-a456-426614174000/hangup
```

---

### Удалить звонок

**DELETE** `/api/calls/{call_id}`

⚠️ Необратимая операция!

```bash
curl -X DELETE http://localhost:8000/api/calls/123e4567-e89b-12d3-a456-426614174000
```

---

## 🧪 Тестовый сценарий

### Полный цикл тестирования:

```bash
# 1. Проверить health
curl http://localhost:8000/health

# 2. Инициировать звонок
CALL_ID=$(curl -X POST "http://localhost:8000/api/calls/initiate" \
  -H "Content-Type: application/json" \
  -d '{"phone": "+79991234567"}' | jq -r '.id')

echo "Call ID: $CALL_ID"

# 3. Получить информацию о звонке
curl http://localhost:8000/api/calls/$CALL_ID

# 4. Получить сообщения
curl http://localhost:8000/api/calls/$CALL_ID/messages

# 5. Завершить звонок
curl -X POST http://localhost:8000/api/calls/$CALL_ID/hangup

# 6. Проверить финальный статус
curl http://localhost:8000/api/calls/$CALL_ID
```

---

## 📊 Swagger UI

Интерактивная документация доступна по адресу:

```
http://localhost:8000/docs
```

Здесь можно тестировать все endpoints прямо из браузера!

---

## 🔍 Проверка NovoFon API

### Проверить доступность NovoFon API:

```bash
curl http://localhost:8000/health/novofon
```

Если `status: "unhealthy"`:
1. Проверьте `NOVOFON_API_KEY` в `.env`
2. Проверьте `NOVOFON_API_URL`
3. Проверьте интернет-соединение
4. Посмотрите логи в `logs/app.log`

---

## 🐛 Troubleshooting

### Ошибка: "Authentication failed"
- Проверьте правильность API ключа NovoFon
- Убедитесь, что ключ активен

### Ошибка: "Database connection failed"
- Проверьте, что PostgreSQL запущен
- Проверьте `DATABASE_URL` в `.env`
- Создайте базу данных: `createdb novofon_bot`

### Ошибка: "Call failed"
- Проверьте формат номера телефона (должен начинаться с +)
- Проверьте баланс на NovoFon аккаунте
- Проверьте, что номер `NOVOFON_FROM_NUMBER` правильный

### Логи

Все логи сохраняются в `logs/app.log`:

```bash
tail -f logs/app.log
```

---

## 📝 Статусы звонков

| Статус | Описание |
|--------|----------|
| `pending` | Звонок создан, ожидает инициации |
| `ringing` | Звонок инициирован, идёт набор |
| `in_progress` | Звонок активен, идёт диалог |
| `completed` | Звонок успешно завершён |
| `no_answer` | Абонент не ответил |
| `busy` | Абонент занят |
| `failed` | Ошибка при звонке |
| `user_hangup` | Абонент завершил звонок |
| `bot_hangup` | Бот завершил звонок |

---

## 🎯 Следующие шаги

После успешного тестирования NovoFon API:

1. ✅ **Этап 2 завершён** - NovoFon интеграция работает
2. 🔄 **Этап 3** - Asterisk + ARI (обработка аудио)
3. 🔄 **Этап 4** - ElevenLabs ASR/TTS
4. 🔄 **Этап 5** - FSM логика диалога
5. 🔄 **Этап 6** - Очередь обзвона

