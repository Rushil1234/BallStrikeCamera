#!/usr/bin/env bash
# TrueCarry Bridge — double-click this file on Mac to run.
# macOS will ask for Bluetooth permission the first time.

cd "$(dirname "$0")"

echo "============================================"
echo "  TrueCarry Bridge  |  truecarry.app"
echo "============================================"
echo ""

# Check Python 3
if ! command -v python3 &>/dev/null; then
    echo "Python 3 is not installed."
    echo ""
    echo "Install it from https://www.python.org/downloads/"
    echo "Then double-click this file again."
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
fi

# Install bleak if needed
echo "Checking dependencies..."
if ! python3 -c "import bleak" &>/dev/null; then
    echo "Installing Bluetooth library (first-time only, ~30 seconds)..."
    pip3 install bleak --quiet
fi

echo "Starting TrueCarry Bridge..."
echo ""
python3 bridge.py

read -n 1 -s -r -p "Press any key to exit..."
