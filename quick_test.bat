@echo off
echo ========================================
echo NovoFon Bot - Quick Test
echo ========================================
echo.

REM Check if .env exists
if not exist .env (
    echo [ERROR] File .env not found!
    echo.
    echo Please create .env file first:
    echo 1. Copy contents from your_env_config.txt
    echo 2. Save as .env in project root
    echo.
    pause
    exit /b 1
)

echo [OK] .env file found
echo.

REM Activate venv
if exist venv\Scripts\activate.bat (
    echo Activating virtual environment...
    call venv\Scripts\activate.bat
) else (
    echo [WARNING] Virtual environment not found
    echo Please create it: python -m venv venv
    echo.
)

echo.
echo ========================================
echo Installing dependencies...
echo ========================================
echo.

pip install httpx python-dotenv aiosqlite

echo.
echo ========================================
echo Testing NovoFon API...
echo ========================================
echo.

python test_novofon_simple.py

echo.
echo ========================================
echo Test complete!
echo ========================================
echo.
echo Next steps:
echo 1. Install all dependencies: pip install -r requirements.txt
echo 2. Run server: python run_dev.py
echo 3. Open browser: http://localhost:8000/docs
echo.

pause

