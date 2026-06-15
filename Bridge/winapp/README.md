# TrueCarry Bridge — Windows app

A system-tray version of the bridge ([../truecarry_tray.py](../truecarry_tray.py)),
packaged into a standalone `.exe` so users don't need Python.

## Build (on a Windows machine)

1. Install Python 3 from python.org (check **Add Python to PATH**).
2. From the `Bridge\` folder, run:
   ```
   winapp\build-windows.bat
   ```
   Output: `winapp\dist\TrueCarry Bridge\TrueCarry Bridge.exe`

PyInstaller can't cross-compile, so this must run on Windows — it can't be
built from the Mac.

## Signing (removes the SmartScreen warning)

Unlike macOS, this is **not** covered by an Apple Developer account. You need a
Windows **code-signing certificate** (OV or EV) from a vendor like DigiCert or
Sectigo (~$200–400/yr). With the cert installed:

```
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a ^
  "winapp\dist\TrueCarry Bridge\TrueCarry Bridge.exe"
```

Then zip the `TrueCarry Bridge` folder and host it for download.

> Until a Windows cert exists, keep the one-command PowerShell installer
> (`irm https://truecarry.vercel.app/downloads/install.ps1 | iex`) as the
> Windows path — it avoids SmartScreen because nothing is downloaded as a
> blocked file.
