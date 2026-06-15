#!/usr/bin/env bash
# TrueCarry Bridge — one-command installer for macOS / Linux.
# Run with:  curl -fsSL https://truecarry.vercel.app/downloads/install.sh | bash
#
# Piping to bash means macOS never quarantines anything, so there's no
# "unverified developer" warning. It sets up an isolated Python environment,
# installs the one dependency, and launches the bridge.

set -e

BASE_URL="https://truecarry.vercel.app/downloads"
DIR="$HOME/.truecarry"

echo "============================================"
echo "  TrueCarry Bridge"
echo "============================================"
echo ""

# 1. Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required."
    echo "A macOS dialog may appear to install the Command Line Tools — accept it,"
    echo "then run this command again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
fi

mkdir -p "$DIR"

# 2. Isolated environment (avoids messing with system Python)
if [ ! -d "$DIR/venv" ]; then
    echo "Setting up (first time only)…"
    python3 -m venv "$DIR/venv"
fi

# 3. Dependency — only install if missing
if ! "$DIR/venv/bin/python" -c "import bleak" >/dev/null 2>&1; then
    echo "Installing Bluetooth library…"
    "$DIR/venv/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 || true
    "$DIR/venv/bin/pip" install --quiet bleak
fi

# 4. Always fetch the latest bridge
curl -fsSL "$BASE_URL/bridge.py" -o "$DIR/bridge.py"

# 5. Run it — reconnect stdin to the terminal so prompts work under curl|bash
echo ""
exec "$DIR/venv/bin/python" "$DIR/bridge.py" < /dev/tty
