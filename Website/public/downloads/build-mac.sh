#!/usr/bin/env bash
# Builds TrueCarry-Bridge as a standalone macOS binary via PyInstaller.
# Run from the Bridge/ directory: bash build-mac.sh
set -e

echo "==> Installing dependencies…"
pip3 install --quiet bleak pyinstaller

echo "==> Building TrueCarry-Bridge…"
pyinstaller --onefile --name "TrueCarry-Bridge" bridge.py

echo ""
echo "✅  Done!  Binary: dist/TrueCarry-Bridge"
echo "    Double-click it (or run ./dist/TrueCarry-Bridge) to start the bridge."
