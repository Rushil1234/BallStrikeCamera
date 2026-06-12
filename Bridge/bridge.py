#!/usr/bin/env python3
"""
TrueCarry Bridge — relays BLE shot data from True Carry iOS app to GSPro / OGS on localhost.

Usage:
  python bridge.py                 # run interactively
  python bridge.py --setup-startup # install as auto-start service, then run

Requirements:
  pip install bleak
"""

import asyncio
import json
import socket
import sys
import os
import struct
import argparse
import platform
from bleak import BleakScanner, BleakClient, BleakError

# ── UUIDs must match SimBLEPeripheral.swift ──────────────────────────────────
SERVICE_UUID = "12e61727-b41a-436e-a1a4-bf0a6c7ec7bc"
SHOT_UUID    = "12e61728-b41a-436e-a1a4-bf0a6c7ec7bc"   # Notify → bridge receives shots
STATUS_UUID  = "12e61729-b41a-436e-a1a4-bf0a6c7ec7bc"   # Write  → bridge sends status back

# ── Simulator ports ──────────────────────────────────────────────────────────
GSPRO_PORT = 921
OGS_PORT   = 3111

# ── State ────────────────────────────────────────────────────────────────────
tcp_writer: asyncio.StreamWriter | None = None
tcp_port: int | None = None
ble_client: BleakClient | None = None
shot_count = 0


def clear():
    os.system("cls" if platform.system() == "Windows" else "clear")


def banner():
    print("=" * 52)
    print("  TrueCarry Bridge  |  truecarry.app/bridge")
    print("=" * 52)


def status_line(label: str, value: str, ok: bool | None = None):
    icon = "✅" if ok is True else ("❌" if ok is False else "⏳")
    print(f"  {icon}  {label:<22} {value}")


def print_status(sim_name: str | None, sim_ok: bool, ble_connected: bool, ble_ready: bool):
    clear()
    banner()
    print()
    status_line("Simulator",    sim_name or "not found",  sim_ok)
    status_line("iPhone (BLE)", "connected" if ble_connected else "searching…", ble_connected)
    status_line("Bridge ready", "yes" if ble_ready else "no",                   ble_ready)
    if shot_count:
        print(f"\n  🏌️  Shots relayed: {shot_count}")
    print()
    if ble_ready:
        print("  Swing away! Each shot is forwarded automatically.")
    else:
        print("  Open True Carry → Sim Mode → Bluetooth on your iPhone.")
    print()


# ── TCP helpers ───────────────────────────────────────────────────────────────

async def find_simulator() -> tuple[int, str] | None:
    """Return (port, name) for the first simulator found on localhost."""
    for port, name in [(GSPRO_PORT, "GSPro"), (OGS_PORT, "OpenGolfSim")]:
        try:
            r, w = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", port), timeout=1.0
            )
            w.close()
            await w.wait_closed()
            return port, name
        except Exception:
            pass
    return None


async def ensure_tcp(port: int) -> bool:
    global tcp_writer, tcp_port
    if tcp_writer and not tcp_writer.is_closing():
        return True
    try:
        _, tcp_writer = await asyncio.wait_for(
            asyncio.open_connection("127.0.0.1", port), timeout=2.0
        )
        tcp_port = port
        return True
    except Exception:
        tcp_writer = None
        return False


async def forward_shot(data: bytes) -> bool:
    global shot_count
    if not tcp_port:
        return False
    ok = await ensure_tcp(tcp_port)
    if not ok or not tcp_writer:
        return False
    try:
        tcp_writer.write(data)
        await tcp_writer.drain()
        shot_count += 1
        return True
    except Exception:
        tcp_writer = None
        return False


# ── BLE status write ──────────────────────────────────────────────────────────

async def send_status(client: BleakClient, port: int, linked: bool):
    payload = json.dumps({"port": port, "linked": linked}).encode()
    try:
        await client.write_gatt_char(STATUS_UUID, payload, response=False)
    except Exception:
        pass


# ── Main loop ─────────────────────────────────────────────────────────────────

async def run():
    global ble_client

    # 1. Find simulator
    result = await find_simulator()
    sim_port, sim_name = result if result else (None, None)
    sim_ok = result is not None

    print_status(sim_name, sim_ok, False, False)

    if not sim_ok:
        print("  ⚠️  Could not reach GSPro or OpenGolfSim on localhost.")
        print("     Make sure your simulator is running, then restart TrueCarry Bridge.")
        print()
        input("  Press Enter to exit…")
        return

    # 2. Scan for iPhone
    print(f"  Scanning for True Carry iPhone app…  (Ctrl+C to quit)\n")

    def on_shot(_, data: bytes):
        asyncio.ensure_future(_relay(data))

    async def _relay(data: bytes):
        await forward_shot(data)
        print_status(sim_name, True, True, True)

    while True:
        try:
            device = await BleakScanner.find_device_by_filter(
                lambda d, _: SERVICE_UUID.lower() in (d.metadata.get("uuids") or []),
                timeout=15.0,
            )
        except BleakError as e:
            print(f"  BLE scan error: {e}")
            await asyncio.sleep(3)
            continue

        if device is None:
            print_status(sim_name, sim_ok, False, False)
            await asyncio.sleep(2)
            continue

        print_status(sim_name, sim_ok, True, False)

        try:
            async with BleakClient(device) as client:
                ble_client = client
                await client.start_notify(SHOT_UUID, on_shot)
                await send_status(client, sim_port, True)
                print_status(sim_name, sim_ok, True, True)

                # Keep alive until disconnected
                while client.is_connected:
                    await asyncio.sleep(1)

                await send_status(client, sim_port, False)

        except BleakError as e:
            pass
        finally:
            ble_client = None

        print_status(sim_name, sim_ok, False, False)
        await asyncio.sleep(2)


# ── Auto-startup helpers ──────────────────────────────────────────────────────

def setup_startup_windows():
    import winreg
    exe = sys.executable if getattr(sys, "frozen", False) else f'pythonw "{os.path.abspath(__file__)}"'
    key = winreg.OpenKey(
        winreg.HKEY_CURRENT_USER,
        r"Software\Microsoft\Windows\CurrentVersion\Run",
        0, winreg.KEY_SET_VALUE
    )
    winreg.SetValueEx(key, "TrueCarryBridge", 0, winreg.REG_SZ, exe)
    winreg.CloseKey(key)
    print("✅  Added to Windows startup (HKCU\\…\\Run).")


def setup_startup_mac():
    plist_dir  = os.path.expanduser("~/Library/LaunchAgents")
    plist_path = os.path.join(plist_dir, "app.truecarry.bridge.plist")
    os.makedirs(plist_dir, exist_ok=True)

    if getattr(sys, "frozen", False):
        program = sys.executable
    else:
        program = os.path.abspath(__file__)

    plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>app.truecarry.bridge</string>
    <key>ProgramArguments</key>
    <array><string>{program}</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/truecarry-bridge.log</string>
    <key>StandardErrorPath</key><string>/tmp/truecarry-bridge.log</string>
</dict>
</plist>
"""
    with open(plist_path, "w") as f:
        f.write(plist)

    os.system(f"launchctl load {plist_path}")
    print(f"✅  LaunchAgent installed: {plist_path}")
    print("    TrueCarry Bridge will now start automatically at login.")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="TrueCarry BLE→TCP Bridge")
    parser.add_argument("--setup-startup", action="store_true",
                        help="Install as an auto-start service, then run normally")
    args = parser.parse_args()

    if args.setup_startup:
        if platform.system() == "Windows":
            setup_startup_windows()
        else:
            setup_startup_mac()
        print()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\n  Bye!")


if __name__ == "__main__":
    main()
