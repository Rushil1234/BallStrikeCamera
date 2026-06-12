# TrueCarry Bridge

Relays shot data from the **True Carry** iOS app to **GSPro** or **OpenGolfSim** on your PC/Mac via Bluetooth — no Wi-Fi required.

## How it works

1. True Carry advertises a BLE GATT service.
2. This bridge connects as a BLE central and receives shot notifications.
3. Each shot is forwarded over TCP to `127.0.0.1:921` (GSPro) or `127.0.0.1:3111` (OGS).
4. The bridge reports its status back to the iPhone so the app UI updates.

## Quick start (pre-built binary)

Download `TrueCarry-Bridge.exe` (Windows) or `TrueCarry-Bridge` (Mac) from **truecarry.app/bridge** and double-click it.

## Build from source

**Mac:**
```bash
bash build-mac.sh
```

**Windows:**
```
Double-click build-windows.bat
```

Requires Python 3.9+ and pip. PyInstaller and bleak are installed automatically.

## Auto-start at login

```
TrueCarry-Bridge --setup-startup
```

This adds the bridge to Windows Startup (registry) or installs a Mac LaunchAgent so it runs automatically every time you log in.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Could not reach GSPro / OGS" | Start your simulator first, then launch the bridge |
| iPhone not found | Make sure True Carry is open on the Sim Mode → Bluetooth screen |
| Bluetooth permission denied (Mac) | System Settings → Privacy → Bluetooth → allow Terminal / TrueCarry-Bridge |
| Bluetooth permission denied (Windows) | Settings → Bluetooth & devices → make sure Bluetooth is on |
