"""
Interactive setup script for NovoFon Bot
Helps configure .env file with proper credentials
"""
import os
from pathlib import Path


def setup_environment():
    """Interactive environment setup"""
    
    print("=" * 60)
    print("🤖 NovoFon Bot - Environment Setup")
    print("=" * 60)
    print()
    
    # Check if .env exists
    env_file = Path(".env")
    if env_file.exists():
        print("⚠️  .env file already exists!")
        response = input("Overwrite? (y/n): ").strip().lower()
        if response != 'y':
            print("Cancelled. Edit .env manually.")
            return
    
    print("\n📝 Please provide the following information:\n")
    
    # Collect information
    config = {}
    
    # NovoFon
    print("--- NovoFon API ---")
    config['NOVOFON_API_KEY'] = input("NovoFon API Key: ").strip()
    config['NOVOFON_FROM_NUMBER'] = input("Your NovoFon phone number (e.g., +79991234567): ").strip()
    config['NOVOFON_API_URL'] = input("NovoFon API URL (press Enter for default): ").strip() or "https://api.novofon.com"
    
    print("\n--- ElevenLabs (можно пропустить, будет нужен на Этапе 4) ---")
    config['ELEVENLABS_API_KEY'] = input("ElevenLabs API Key (optional, press Enter to skip): ").strip() or "your_elevenlabs_api_key_here"
    config['ELEVENLABS_VOICE_ID'] = input("ElevenLabs Voice ID (press Enter for default): ").strip() or "21m00Tcm4TlvDq8ikWAM"
    
    print("\n--- Database ---")
    db_user = input("PostgreSQL username (default: novofon_user): ").strip() or "novofon_user"
    db_password = input("PostgreSQL password (default: password): ").strip() or "password"
    db_host = input("PostgreSQL host (default: localhost): ").strip() or "localhost"
    db_port = input("PostgreSQL port (default: 5432): ").strip() or "5432"
    db_name = input("PostgreSQL database name (default: novofon_bot): ").strip() or "novofon_bot"
    
    config['DATABASE_URL'] = f"postgresql+asyncpg://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    
    # Write .env file
    print("\n" + "=" * 60)
    print("✍️  Writing .env file...")
    
    env_content = f"""# Application
APP_ENV=development
APP_HOST=0.0.0.0
APP_PORT=8000
DEBUG=true

# Database
DATABASE_URL={config['DATABASE_URL']}

# NovoFon API
NOVOFON_API_KEY={config['NOVOFON_API_KEY']}
NOVOFON_API_URL={config['NOVOFON_API_URL']}
NOVOFON_FROM_NUMBER={config['NOVOFON_FROM_NUMBER']}

# ElevenLabs
ELEVENLABS_API_KEY={config['ELEVENLABS_API_KEY']}
ELEVENLABS_VOICE_ID={config['ELEVENLABS_VOICE_ID']}
ELEVENLABS_MODEL=eleven_turbo_v2

# Asterisk ARI (будет настроено на Этапе 3)
ASTERISK_ARI_URL=http://localhost:8088/ari
ASTERISK_ARI_USERNAME=asterisk
ASTERISK_ARI_PASSWORD=asterisk
ASTERISK_ARI_APP_NAME=novofon_bot

# Redis (будет нужен на Этапе 6)
REDIS_URL=redis://localhost:6379/0

# Celery (будет нужен на Этапе 6)
CELERY_BROKER_URL=redis://localhost:6379/1
CELERY_RESULT_BACKEND=redis://localhost:6379/2

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/app.log
"""
    
    with open(".env", "w", encoding="utf-8") as f:
        f.write(env_content)
    
    print("✅ .env file created successfully!")
    print()
    print("=" * 60)
    print("📋 Next steps:")
    print("=" * 60)
    print()
    print("1. Install dependencies:")
    print("   pip install -r requirements.txt")
    print()
    print("2. Setup PostgreSQL database:")
    print(f"   createdb {db_name}")
    print("   OR")
    print(f"   psql -U postgres -c \"CREATE DATABASE {db_name};\"")
    print()
    print("3. Run the application:")
    print("   python run_dev.py")
    print()
    print("4. Test API:")
    print("   Open http://localhost:8000/docs")
    print()
    print("=" * 60)
    print("🎉 Setup complete! Ready to test!")
    print("=" * 60)


if __name__ == "__main__":
    try:
        setup_environment()
    except KeyboardInterrupt:
        print("\n\n❌ Setup cancelled.")
    except Exception as e:
        print(f"\n\n❌ Error: {e}")

