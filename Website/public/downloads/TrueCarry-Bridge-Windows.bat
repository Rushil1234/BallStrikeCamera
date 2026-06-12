@echo off
title TrueCarry Bridge
echo ============================================
echo   TrueCarry Bridge  ^|  truecarry.app
echo ============================================
echo.

REM Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python is not installed.
    echo.
    echo Please install Python from https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation.
    echo Then double-click this file again.
    echo.
    pause
    exit /b 1
)

REM Install bleak if needed
echo Checking dependencies...
pip show bleak >nul 2>&1
if %errorlevel% neq 0 (
    echo Installing Bluetooth library ^(first-time only, takes ~30 seconds^)...
    pip install bleak --quiet
    if %errorlevel% neq 0 (
        echo Failed to install bleak. Check your internet connection.
        pause
        exit /b 1
    )
)

REM Run
echo Starting TrueCarry Bridge...
echo.
python bridge.py
pause
