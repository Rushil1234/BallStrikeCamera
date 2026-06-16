#!/usr/bin/env python3
"""
TrueCarry Bridge — macOS menu-bar app.

Wraps bridge.py (the BLE→TCP relay) in a small menu-bar UI:
  • a golf icon in the menu bar shows live status,
  • "Open status page" launches truecarry.app/connect,
  • "Quit" stops everything (added automatically by rumps).

The bridge's asyncio loop runs on a background thread; rumps owns the main
thread and polls bridge.STATE once a second to update the menu.
"""

import asyncio
import threading
import webbrowser

import rumps

import bridge

CONNECT_URL = "https://truecarry.vercel.app/connect"


class BridgeApp(rumps.App):
    def __init__(self):
        super().__init__("TrueCarry", title="⛳︎", quit_button="Quit")
        self.status_item = rumps.MenuItem("Starting…")
        self.menu = [
            self.status_item,
            None,  # separator
            rumps.MenuItem("Open status page", callback=self.open_status),
        ]
        threading.Thread(target=self._run_bridge, daemon=True).start()
        rumps.Timer(self._tick, 1).start()
        # Make it obvious the (window-less) app actually launched.
        self._announced = False
        rumps.Timer(self._announce, 1).start()

    def _announce(self, timer):
        if self._announced:
            return
        self._announced = True
        timer.stop()
        try:
            rumps.notification(
                "TrueCarry Bridge is running",
                "Look for the ⛳︎ icon in your menu bar.",
                "Open Sim Mode → Bluetooth on your iPhone to connect.",
            )
        except Exception:
            pass

    def _run_bridge(self):
        try:
            asyncio.run(bridge.run())
        except Exception:
            # Bridge crashed/stopped — menu will keep showing last known state.
            pass

    def _tick(self, _):
        s = bridge.STATE
        if s.get("ready"):
            self.title = "⛳︎ ✓"
            self.status_item.title = f"Connected — {s.get('sim') or 'simulator'}"
        elif not s.get("simFound"):
            self.title = "⛳︎ …"
            self.status_item.title = "Waiting for GSPro / OpenGolfSim"
        else:
            self.title = "⛳︎ …"
            self.status_item.title = f"{s.get('sim') or 'Sim'} ready — open Sim Mode on iPhone"

    def open_status(self, _):
        webbrowser.open(CONNECT_URL)


if __name__ == "__main__":
    BridgeApp().run()
