#!/usr/bin/env bash
set -e

# Wine MT5 path on macOS
WINE_MT5_BASE="$HOME/mt5prefix/drive_c/Program Files/MetaTrader 5/MQL5"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Setting up Symlinks for MetaTrader 5 on Wine ==="
echo "Project Directory : $PROJECT_DIR"
echo "MT5 MQL5 Target   : $WINE_MT5_BASE"

if [ ! -d "$WINE_MT5_BASE" ]; then
    echo "Error: MT5 directory not found at $WINE_MT5_BASE"
    echo "Please adjust the path in this script to match your Wine MT5 installation."
    exit 1
fi

# Ensure project subfolders exist
mkdir -p "$PROJECT_DIR/experts"
mkdir -p "$PROJECT_DIR/include"

# Create symlinks
TARGET_EXPERTS="$WINE_MT5_BASE/Experts/TradingRepo"
TARGET_INCLUDE="$WINE_MT5_BASE/Include/TradingRepo"

if [ -L "$TARGET_EXPERTS" ] || [ -d "$TARGET_EXPERTS" ]; then
    echo "Removing existing symlink / folder: $TARGET_EXPERTS"
    rm -rf "$TARGET_EXPERTS"
fi
ln -s "$PROJECT_DIR/experts" "$TARGET_EXPERTS"
echo " Linked: $TARGET_EXPERTS -> $PROJECT_DIR/experts"

if [ -L "$TARGET_INCLUDE" ] || [ -d "$TARGET_INCLUDE" ]; then
    echo "Removing existing symlink / folder: $TARGET_INCLUDE"
    rm -rf "$TARGET_INCLUDE"
fi
ln -s "$PROJECT_DIR/include" "$TARGET_INCLUDE"
echo " Linked: $TARGET_INCLUDE -> $PROJECT_DIR/include"

echo "=== Symlink setup completed successfully! ==="
echo "You can now open MetaEditor in Wine, and 'TradingRepo' will appear under Experts and Include."
