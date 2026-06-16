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
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from bleak import BleakScanner, BleakClient, BleakError

# ── UUIDs must match SimBLEPeripheral.swift ──────────────────────────────────
SERVICE_UUID = "12e61727-b41a-436e-a1a4-bf0a6c7ec7bc"
SHOT_UUID    = "12e61728-b41a-436e-a1a4-bf0a6c7ec7bc"   # Notify → bridge receives shots
STATUS_UUID  = "12e61729-b41a-436e-a1a4-bf0a6c7ec7bc"   # Write  → bridge sends status back

# ── Simulator ports ──────────────────────────────────────────────────────────
GSPRO_PORT = 921
OGS_PORT   = 3111

# ── Local status server ───────────────────────────────────────────────────────
# A tiny HTTP server on localhost so truecarry.app/connect can show live status
# in this computer's browser (the iPhone can't reach this — that's the point of BLE).
STATUS_HTTP_PORT = 8421

# ── State ────────────────────────────────────────────────────────────────────
tcp_writer: asyncio.StreamWriter | None = None
tcp_port: int | None = None
detected_port: int | None = None
sim_name: str | None = None
ble_client: BleakClient | None = None
ble_connected = False
ble_ready = False
shot_count = 0

# Shared snapshot read by the local status server (updated in refresh_status).
STATE: dict = {
    "running": True,
    "sim": None,
    "simFound": False,
    "bleConnected": False,
    "ready": False,
    "port": None,
    "shots": 0,
}


def clear():
    if not sys.stdout.isatty():
        return  # running inside the .app (no console) — nothing to clear
    os.system("cls" if platform.system() == "Windows" else "clear")


def banner():
    print("=" * 52)
    print("  TrueCarry Bridge  |  truecarry.app/bridge")
    print("=" * 52)


def status_line(label: str, value: str, ok: bool | None = None):
    icon = "✅" if ok is True else ("❌" if ok is False else "⏳")
    print(f"  {icon}  {label:<22} {value}")


def refresh_status():
    """Recompute STATE from the current globals and redraw the console."""
    sim_found = detected_port is not None
    STATE.update({
        "sim": sim_name,
        "simFound": sim_found,
        "bleConnected": ble_connected,
        "ready": ble_ready,
        "port": detected_port,
        "shots": shot_count,
    })
    clear()
    banner()
    print()
    status_line("Simulator",    sim_name or "not found",                         sim_found)
    status_line("iPhone (BLE)", "connected" if ble_connected else "searching…",  ble_connected)
    status_line("Bridge ready", "yes" if ble_ready else "no",                    ble_ready)
    if shot_count:
        print(f"\n  🏌️  Shots relayed: {shot_count}")
    print()
    if ble_ready and sim_found:
        print(f"  Swing away! Forwarding every shot to {sim_name}.")
    elif not sim_found:
        print("  Waiting for GSPro or OpenGolfSim on this computer…")
    else:
        print("  Open True Carry → Sim Mode → Bluetooth on your iPhone.")
    print()


# ── Local status server ─────────────────────────────────────────────────────

class _StatusHandler(BaseHTTPRequestHandler):
    """Serves the current STATE as JSON so the website can show live status."""

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def do_GET(self):
        if self.path.split("?")[0] not in ("/", "/status"):
            self.send_response(404)
            self._cors()
            self.end_headers()
            return
        body = json.dumps(STATE).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # keep the console clean


def start_status_server():
    """Best-effort: start the localhost status server in a daemon thread."""
    try:
        server = ThreadingHTTPServer(("127.0.0.1", STATUS_HTTP_PORT), _StatusHandler)
    except OSError:
        return  # port in use (another bridge already running) — not fatal
    threading.Thread(target=server.serve_forever, daemon=True).start()


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
    global shot_count, tcp_writer
    if not detected_port:
        return False
    ok = await ensure_tcp(detected_port)
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

def _matches_truecarry(device, adv) -> bool:
    """True if this BLE advertisement is the True Carry iPhone app.

    bleak 3.x removed BLEDevice.metadata; the advertised service UUIDs now
    live on the advertisement_data passed to the scan filter.
    """
    uuids = [u.lower() for u in (getattr(adv, "service_uuids", None) or [])]
    if SERVICE_UUID.lower() in uuids:
        return True
    name = getattr(adv, "local_name", None) or getattr(device, "name", None) or ""
    return name == "TrueCarry"


async def monitor_simulator():
    """Continuously track which simulator is running, so the user can switch
    between GSPro and OGS (or start one later) without restarting the bridge.

    On a change we drop the old TCP link and re-tell the phone which game we're
    on now — the app encodes shots differently for GSPro vs OGS.
    """
    global detected_port, sim_name, tcp_writer
    while True:
        result = await find_simulator()
        new_port = result[0] if result else None
        new_name = result[1] if result else None
        if new_port != detected_port:
            detected_port = new_port
            sim_name = new_name
            # Drop any link to the old sim; the next shot reconnects to the new one.
            if tcp_writer:
                try:
                    tcp_writer.close()
                except Exception:
                    pass
                tcp_writer = None
            # If the phone is connected, tell it the new game/port immediately.
            if ble_client and new_port:
                await send_status(ble_client, new_port, True)
            refresh_status()
        await asyncio.sleep(3)


async def send_status(client: BleakClient, port: int, linked: bool):
    payload = json.dumps({"port": port, "linked": linked}).encode()
    try:
        await client.write_gatt_char(STATUS_UUID, payload, response=False)
    except Exception:
        pass


# ── Main loop ─────────────────────────────────────────────────────────────────

async def run():
    global ble_client, ble_connected, ble_ready

    # 0. Start the local status server so truecarry.app/connect can see us.
    start_status_server()

    # 1. Continuously detect which simulator is running (GSPro or OGS).
    asyncio.ensure_future(monitor_simulator())
    refresh_status()
    while detected_port is None:
        await asyncio.sleep(1)

    # 2. Scan for the iPhone.
    print("  Scanning for True Carry iPhone app…  (Ctrl+C to quit)\n")

    def on_shot(_, data: bytes):
        asyncio.ensure_future(_relay(data))

    async def _relay(data: bytes):
        await forward_shot(data)
        refresh_status()

    while True:
        try:
            # Scan FOR our specific service UUID. iOS only surfaces a custom
            # 128-bit service to a central that explicitly scans for it
            # (especially once the advertisement moves to the overflow area),
            # so a scan-for-everything can miss the iPhone entirely.
            device = await BleakScanner.find_device_by_filter(
                _matches_truecarry,
                timeout=15.0,
                service_uuids=[SERVICE_UUID],
            )
        except BleakError as e:
            print(f"  BLE scan error: {e}")
            await asyncio.sleep(3)
            continue

        if device is None:
            ble_connected = False
            ble_ready = False
            refresh_status()
            await asyncio.sleep(2)
            continue

        ble_connected = True
        ble_ready = False
        refresh_status()

        try:
            async with BleakClient(device) as client:
                ble_client = client
                await client.start_notify(SHOT_UUID, on_shot)
                # Open the TCP link to the current sim now so it shows
                # "connected" immediately, rather than only after the first shot.
                if detected_port:
                    await ensure_tcp(detected_port)
                    await send_status(client, detected_port, True)
                ble_ready = True
                refresh_status()

                # Keep alive until disconnected
                while client.is_connected:
                    await asyncio.sleep(1)

                if detected_port:
                    await send_status(client, detected_port, False)

        except BleakError:
            pass
        finally:
            ble_client = None
            ble_connected = False
            ble_ready = False

        refresh_status()
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
