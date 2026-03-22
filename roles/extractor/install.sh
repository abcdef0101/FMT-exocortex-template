#!/usr/bin/env bash
# Extractor: установка launchd-агента для inbox-check
# Targets: macOS (launchd), Linux (systemd)
set -euo pipefail
# Extractor: установка агента обработки inbox (каждые 3 часа)
# macOS: launchd (~/Library/LaunchAgents)
# Linux: systemd user timer (~/.config/systemd/user)


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$SCRIPT_DIR/scripts/launchd/com.extractor.inbox-check.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.extractor.inbox-check.plist"

echo "Installing Extractor agent..."

EXTRACTOR_SH="$SCRIPT_DIR/scripts/extractor.sh"

# Делаем скрипты исполняемыми
chmod +x "$EXTRACTOR_SH"
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

if [[ "$OSTYPE" == "darwin"* ]]; then
    # === macOS: launchd ===
    if [ ! -f "$PLIST_SRC" ]; then
        echo "ERROR: $PLIST_SRC not found"
        exit 1
    fi

    # Выгружаем старый агент (если есть)
    launchctl unload "$PLIST_DST" 2>/dev/null || true

    # Копируем plist и загружаем
    cp "$PLIST_SRC" "$PLIST_DST"
    launchctl load "$PLIST_DST"

    echo "  ✓ Installed: com.extractor.inbox-check (launchd)"
    echo "  ✓ Interval: every 3 hours"
    echo "  ✓ Logs: ~/.local/state/logs/extractor/"
    echo ""
    echo "Verify: launchctl list | grep extractor"
    echo "Uninstall: launchctl unload $PLIST_DST && rm $PLIST_DST"
else
    # === Linux: systemd user timer ===
    mkdir -p "$HOME/.local/state/logs/extractor"
    SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    cp "$SYSTEMD_SRC/exocortex-extractor.service" "$SYSTEMD_DIR/"
    cp "$SYSTEMD_SRC/exocortex-extractor.timer"   "$SYSTEMD_DIR/"

    systemctl --user daemon-reload
    systemctl --user enable --now exocortex-extractor.timer

    echo "  ✓ Installed: exocortex-extractor.timer (systemd user)"
    echo "  ✓ Schedule: every 3h (07,10,13,16,19,22:00)"
    echo "  ✓ Logs: ~/.local/state/logs/extractor/systemd-inbox-check.log"
    echo ""
    echo "Verify: systemctl --user list-timers | grep exocortex"
    echo "Logs:   journalctl --user -u exocortex-extractor.service -f"
    echo ""
    echo "Uninstall:"
    echo "  systemctl --user disable --now exocortex-extractor.timer"
    echo "  rm $SYSTEMD_DIR/exocortex-extractor.{service,timer}"
    echo "  systemctl --user daemon-reload"
fi
