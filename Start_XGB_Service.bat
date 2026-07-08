@echo off
title XGBoost Auto-Training Service
echo ==================================================
echo Khởi động hệ thống XGBoost Auto-Training Service...
echo ==================================================
cd /d "%~dp0"

echo Dang chay ngam dưới System Tray...
echo Vui long kiem tra goc phai duoi man hinh!
echo.
python tools\xgb_service.py
