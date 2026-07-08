@echo off
title XGB Auto-Training Service
cd /d "%~dp0"

echo ============================================
echo  XGBoost Auto-Training Service
echo  RSI_Advanced V12.2
echo ============================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found in PATH.
    echo Install Python 3.8+ from https://www.python.org/downloads/
    pause
    exit /b 1
)

:: Check dependencies (quick import test)
python -c "import pystray, PIL, plyer" >nul 2>&1
if errorlevel 1 (
    echo Installing dependencies...
    pip install pystray Pillow plyer
    if errorlevel 1 (
        echo ERROR: Failed to install dependencies.
        echo Run manually: pip install pystray Pillow plyer
        pause
        exit /b 1
    )
    echo Dependencies installed.
    echo.
)

:: Check config exists
if not exist "xgb_config.json" (
    echo ERROR: xgb_config.json not found.
    echo Create it in the tools/ folder with your terminal IDs.
    pause
    exit /b 1
)

:: Pre-flight: test import xgb_service.py (catches syntax/import errors with visible output)
echo Checking xgb_service.py...
python -c "import xgb_service" >nul 2>&1
if errorlevel 1 (
    echo ERROR: xgb_service.py has errors:
    echo.
    python -c "import xgb_service"
    echo.
    pause
    exit /b 1
)
echo OK.
echo.

:: Launch service
echo Starting XGB Service (tray icon)...
echo Close via: right-click tray icon ^> Exit
echo.

start "" pythonw xgb_service.py

:: Wait and verify process is alive
timeout /t 3 /nobreak >nul

tasklist /fi "imagename eq pythonw.exe" 2>nul | findstr /i "pythonw" >nul
if errorlevel 1 (
    echo.
    echo ERROR: Service failed to start. Running with console for diagnostics:
    echo.
    python xgb_service.py
    pause
    exit /b 1
)

echo Service launched. Check system tray for gold XG icon.
echo This window will close in 3 seconds...
timeout /t 3 /nobreak >nul
