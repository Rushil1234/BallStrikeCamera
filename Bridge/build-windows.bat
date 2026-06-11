@echo off
REM Builds TrueCarry-Bridge.exe as a standalone Windows executable.
REM Run from the Bridge\ folder: double-click or run from Command Prompt.

echo =^> Installing dependencies...
pip install bleak pyinstaller
if %errorlevel% neq 0 (
    echo.
    echo ERROR: pip failed. Make sure Python 3.9+ is installed from python.org
    pause
    exit /b 1
)

echo =^> Building TrueCarry-Bridge.exe...
pyinstaller --onefile --name "TrueCarry-Bridge" --noconsole bridge.py
if %errorlevel% neq 0 (
    echo.
    echo ERROR: PyInstaller failed. See output above.
    pause
    exit /b 1
)

echo.
echo Done!  Executable: dist\TrueCarry-Bridge.exe
echo Double-click dist\TrueCarry-Bridge.exe to start the bridge.
pause
