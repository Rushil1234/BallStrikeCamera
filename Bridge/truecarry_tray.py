#!/usr/bin/env python3
"""
TrueCarry Bridge — Windows system-tray app.

Windows equivalent of truecarry_menubar.py: shows a tray icon whose colour
reflects status (grey = waiting, amber = sim ready, green = connected), with
"Open status page" and "Quit". The bridge's asyncio loop runs on a background
thread; pystray owns the main thread.

Build on Windows with winapp/build-windows.bat (needs Python 3 installed).
"""

import asyncio
import threading
import time
import webbrowser

import pystray
from pystray import MenuItem as Item
from PIL import Image, ImageDraw

import bridge

CONNECT_URL = "https://truecarry.vercel.app/connect"

GREY = (174, 176, 162, 255)
AMBER = (216, 162, 74, 255)
GREEN = (63, 182, 139, 255)


def _icon(color):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((8, 8, 56, 56), fill=color)
    return img


def _status_text(_=None):
    s = bridge.STATE
    if s.get("ready"):
        return f"Connected — {s.get('sim') or 'simulator'}"
    if not s.get("simFound"):
        return "Waiting for GSPro / OpenGolfSim"
    return f"{s.get('sim') or 'Sim'} ready — open Sim Mode on iPhone"


def main():
    threading.Thread(target=lambda: asyncio.run(bridge.run()), daemon=True).start()

    icon = pystray.Icon("TrueCarry", _icon(GREY), "TrueCarry Bridge")
    icon.menu = pystray.Menu(
        Item(_status_text, None, enabled=False),
        Item("Open status page", lambda: webbrowser.open(CONNECT_URL)),
        Item("Quit", lambda i: i.stop()),
    )

    def refresh():
        while True:
            s = bridge.STATE
            icon.icon = _icon(GREEN if s.get("ready") else AMBER if s.get("simFound") else GREY)
            icon.title = "TrueCarry Bridge — " + _status_text()
            time.sleep(1)

    threading.Thread(target=refresh, daemon=True).start()
    icon.run()


if __name__ == "__main__":
    main()
