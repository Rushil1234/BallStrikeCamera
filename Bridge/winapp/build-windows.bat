@echo off
REM Build the TrueCarry Bridge tray app on Windows with PyInstaller.
REM Run from the Bridge\ folder:  winapp\build-windows.bat
setlocal

cd /d "%~dp0\.."

if not exist "winapp\.buildvenv" (
    echo Creating build venv...
    python -m venv "winapp\.buildvenv"
)
call "winapp\.buildvenv\Scripts\activate.bat"
pip install --quiet --upgrade pip
pip install --quiet pyinstaller pystray pillow bleak

rmdir /s /q "winapp\build" 2>nul
rmdir /s /q "winapp\dist" 2>nul

pyinstaller --noconfirm --clean --windowed ^
    --name "TrueCarry Bridge" ^
    --collect-all bleak ^
    --collect-all pystray ^
    --distpath "winapp\dist" ^
    --workpath "winapp\build" ^
    --specpath "winapp\build" ^
    truecarry_tray.py

echo.
echo Built: winapp\dist\TrueCarry Bridge\TrueCarry Bridge.exe
echo.
echo To remove the SmartScreen warning, sign it with your code-signing cert:
echo   signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a ^
echo     "winapp\dist\TrueCarry Bridge\TrueCarry Bridge.exe"
echo Then zip the "TrueCarry Bridge" folder for distribution.
endlocal
