#!/usr/bin/env bash
set -e

WINE_PREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
METAEDITOR_EXE="$WINE_PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_FILE="$1"
if [ -z "$TARGET_FILE" ]; then
    echo "Usage: ./scripts/compile.sh <path-to-mq5-file>"
    echo "Example: ./scripts/compile.sh experts/StarterEA.mq5"
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    # Try resolving relative to PROJECT_DIR
    if [ -f "$PROJECT_DIR/$TARGET_FILE" ]; then
        TARGET_FILE="$PROJECT_DIR/$TARGET_FILE"
    else
        echo "Error: File not found: $TARGET_FILE"
        exit 1
    fi
else
    TARGET_FILE="$(cd "$(dirname "$TARGET_FILE")" && pwd)/$(basename "$TARGET_FILE")"
fi

LOG_FILE="/tmp/mql5_compile.log"
rm -f "$LOG_FILE"

WIN_TARGET="$(WINEPREFIX="$WINE_PREFIX" winepath -w "$TARGET_FILE" 2>/dev/null | grep -E '^[A-Z]:\\' | tail -n 1)"
WIN_LOG="$(WINEPREFIX="$WINE_PREFIX" winepath -w "$LOG_FILE" 2>/dev/null | grep -E '^[A-Z]:\\' | tail -n 1)"

echo "=== Compiling MQL5 EA with MetaEditor (Wine) ==="
echo "Source : $TARGET_FILE"
echo "Target : $WIN_TARGET"

WINEPREFIX="$WINE_PREFIX" wine "$METAEDITOR_EXE" /compile:"$WIN_TARGET" /log:"$WIN_LOG" 2>/dev/null || true

# Wait briefly for log file to flush
sleep 1

if [ -f "$LOG_FILE" ]; then
    echo "--- Compilation Output ---"
    # Convert potential UTF-16 to UTF-8
    iconv -f UTF-16LE -t UTF-8 "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE"
    echo "--------------------------"
else
    echo "Note: Compilation completed (no log output produced, check MetaEditor GUI if needed)."
fi

# Check if .ex5 was produced
EX5_FILE="${TARGET_FILE%.mq5}.ex5"
if [ -f "$EX5_FILE" ]; then
    echo "SUCCESS: Compiled binary generated at $EX5_FILE"
    exit 0
else
    echo "WARNING: .ex5 binary was not generated or compilation had errors."
    exit 1
fi
