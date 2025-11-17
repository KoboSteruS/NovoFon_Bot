"""
Quick test script for NovoFon API integration
Tests basic connectivity and API functionality
"""
import asyncio
import sys
from pathlib import Path

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.config import settings
from app.services.novofon import NovoFonClient


async def test_novofon_api():
    """Test NovoFon API connectivity"""
    
    print("=" * 60)
    print("🧪 NovoFon API Test")
    print("=" * 60)
    print()
    
    # Check configuration
    print("📋 Configuration:")
    print(f"   API URL: {settings.novofon_api_url}")
    print(f"   API Key: {settings.novofon_api_key[:10]}..." if settings.novofon_api_key else "   API Key: NOT SET")
    print(f"   From Number: {settings.novofon_from_number}")
    print()
    
    if not settings.novofon_api_key or settings.novofon_api_key == "your_novofon_api_key_here":
        print("❌ NovoFon API key not configured!")
        print("   Please run: python setup_env.py")
        return
    
    # Test connectivity
    print("🔍 Testing NovoFon API connectivity...")
    
    async with NovoFonClient() as client:
        try:
            is_healthy = await client.health_check()
            
            if is_healthy:
                print("✅ NovoFon API is accessible!")
                print()
                print("🎉 Ready to make calls!")
                print()
                print("=" * 60)
                print("📝 To test a real call:")
                print("=" * 60)
                print()
                print("1. Start the server:")
                print("   python run_dev.py")
                print()
                print("2. Make a test call (replace with real number):")
                print('   curl -X POST "http://localhost:8000/api/calls/initiate" \\')
                print('     -H "Content-Type: application/json" \\')
                print('     -d \'{"phone": "+79991234567"}\'')
                print()
                print("3. Or use Swagger UI:")
                print("   http://localhost:8000/docs")
                print()
            else:
                print("⚠️  NovoFon API responded but may have issues")
                print("   Check your API key and network connection")
        
        except Exception as e:
            print(f"❌ Error connecting to NovoFon API: {e}")
            print()
            print("Possible issues:")
            print("  - Invalid API key")
            print("  - Network connectivity problems")
            print("  - NovoFon service is down")
            print()
            print("Please check:")
            print("  1. Your API key in .env file")
            print("  2. Internet connection")
            print("  3. NovoFon service status")
    
    print()
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_novofon_api())

