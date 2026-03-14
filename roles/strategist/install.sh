#!/bin/bash
# Strategist: установка агента утреннего планирования
# macOS: launchd (~/Library/LaunchAgents)
# Linux: systemd user timer (~/.config/systemd/user)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/scripts/launchd"
TARGET_DIR="$HOME/Library/LaunchAgents"

echo "Installing Strategist Agent..."

STRATEGIST_SH="$SCRIPT_DIR/scripts/strategist.sh"

# Make script executable
chmod +x "$STRATEGIST_SH"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # === macOS: launchd ===
    # Unload old agents if present
    launchctl unload "$TARGET_DIR/com.strategist.morning.plist" 2>/dev/null || true
    launchctl unload "$TARGET_DIR/com.strategist.weekreview.plist" 2>/dev/null || true

    # Copy new plist files
    cp "$LAUNCHD_DIR/com.strategist.morning.plist" "$TARGET_DIR/"
    cp "$LAUNCHD_DIR/com.strategist.weekreview.plist" "$TARGET_DIR/"

    # Load agents
    launchctl load "$TARGET_DIR/com.strategist.morning.plist"
    launchctl load "$TARGET_DIR/com.strategist.weekreview.plist"

    echo "Done. Agents loaded:"
    launchctl list | grep strategist
else
    # === Linux: systemd user timers ===
    mkdir -p "$HOME/logs/strategist"
    SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    cp "$SYSTEMD_SRC/exocortex-strategist-morning.service"    "$SYSTEMD_DIR/"
    cp "$SYSTEMD_SRC/exocortex-strategist-morning.timer"      "$SYSTEMD_DIR/"
    cp "$SYSTEMD_SRC/exocortex-strategist-weekreview.service" "$SYSTEMD_DIR/"
    cp "$SYSTEMD_SRC/exocortex-strategist-weekreview.timer"   "$SYSTEMD_DIR/"

    systemctl --user daemon-reload
    systemctl --user enable --now exocortex-strategist-morning.timer
    systemctl --user enable --now exocortex-strategist-weekreview.timer

    echo "Done. Timers installed:"
    systemctl --user list-timers | grep exocortex-strategist
fi
