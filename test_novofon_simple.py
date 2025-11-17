"""
Simplified NovoFon API test without database
Just tests API connectivity
"""
import asyncio
import os
from dotenv import load_dotenv
import httpx


async def test_novofon_simple():
    """Simple NovoFon API test"""
    
    # Load .env
    load_dotenv()
    
    api_key = os.getenv("NOVOFON_API_KEY")
    api_url = os.getenv("NOVOFON_API_URL", "https://api.novofon.com")
    
    print("=" * 60)
    print("🧪 NovoFon API Simple Test (без БД)")
    print("=" * 60)
    print()
    print(f"API URL: {api_url}")
    print(f"API Key: {api_key[:10] + '...' if api_key else 'NOT SET'}")
    print()
    
    if not api_key or api_key == "your_novofon_api_key_here":
        print("❌ API Key не настроен!")
        print()
        print("Создайте файл .env в корне проекта:")
        print()
        print("NOVOFON_API_KEY=ваш_ключ_здесь")
        print("NOVOFON_FROM_NUMBER=+79991234567")
        print("NOVOFON_API_URL=https://api.novofon.com")
        print()
        return
    
    print("🔍 Проверяю доступность API...")
    
    try:
        async with httpx.AsyncClient(
            base_url=api_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            },
            timeout=10.0
        ) as client:
            
            # Try to access API
            response = await client.get("/")
            
            print(f"   Status Code: {response.status_code}")
            
            if response.status_code < 500:
                print("✅ NovoFon API доступен!")
                print()
                print("🎉 Готово к использованию!")
                print()
                print("=" * 60)
                print("Следующие шаги:")
                print("=" * 60)
                print()
                print("1. Настройте PostgreSQL (если нужен):")
                print("   createdb novofon_bot")
                print()
                print("2. Запустите сервер:")
                print("   python run_dev.py")
                print()
                print("3. Откройте Swagger UI:")
                print("   http://localhost:8000/docs")
                print()
                print("4. Протестируйте звонок через /api/calls/initiate")
                print()
            else:
                print("⚠️  API вернул ошибку сервера")
                print(f"   Response: {response.text}")
    
    except httpx.ConnectError:
        print("❌ Не удалось подключиться к NovoFon API")
        print()
        print("Проверьте:")
        print("  - Интернет соединение")
        print("  - URL API (NOVOFON_API_URL)")
        print("  - Firewall / прокси настройки")
    
    except httpx.TimeoutException:
        print("❌ Timeout при подключении к API")
        print("   Возможно, медленное соединение или API недоступен")
    
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        print()
        print("Проверьте:")
        print("  - Правильность API ключа")
        print("  - Формат NOVOFON_API_KEY в .env")
    
    print()
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_novofon_simple())

