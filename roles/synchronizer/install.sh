#!/bin/bash
# Synchronizer: установка центрального диспетчера
# macOS: launchd (~/Library/LaunchAgents)
# Linux: systemd user timer (~/.config/systemd/user)
# Заменяет отдельные агенты Стратега единым scheduler
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$SCRIPT_DIR/scripts/launchd/com.exocortex.scheduler.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.exocortex.scheduler.plist"

echo "Installing Synchronizer (central scheduler)..."

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

# Создаём директории состояния
mkdir -p "$HOME/.local/state/exocortex"
mkdir -p "$HOME/logs/synchronizer"

SCHEDULER_SH="$SCRIPT_DIR/scripts/scheduler.sh"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # === macOS: launchd ===
    if [ ! -f "$PLIST_SRC" ]; then
        echo "ERROR: $PLIST_SRC not found"
        exit 1
    fi

    # Выгружаем старые агенты
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.strategist.morning.plist" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.strategist.weekreview.plist" 2>/dev/null || true

    # Копируем и загружаем
    cp "$PLIST_SRC" "$PLIST_DST"
    launchctl load "$PLIST_DST"

    echo "  ✓ Installed: com.exocortex.scheduler (launchd)"
    echo "  ✓ Schedule: 10 dispatch points per day"
    echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
    echo "  ✓ State: ~/.local/state/exocortex/"
    echo "  ✓ Logs: ~/logs/synchronizer/"
    echo ""
    echo "Verify: launchctl list | grep exocortex"
    echo "Status: bash $SCHEDULER_SH status"
    echo ""
    echo "Auto-wake (recommended): plan ready before you wake up"
    echo "  sudo pmset repeat wakeorpoweron MTWRFSU 03:55:00"
    echo "  (Mac must be on power. Cancel: sudo pmset repeat cancel)"
    echo ""
    echo "Uninstall: launchctl unload $PLIST_DST && rm $PLIST_DST"
else
    # === Linux: systemd user timer ===
    SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    cp "$SYSTEMD_SRC/exocortex-scheduler.service" "$SYSTEMD_DIR/"
    cp "$SYSTEMD_SRC/exocortex-scheduler.timer"   "$SYSTEMD_DIR/"

    systemctl --user daemon-reload
    systemctl --user enable --now exocortex-scheduler.timer

    echo "  ✓ Installed: exocortex-scheduler.timer (systemd user)"
    echo "  ✓ Schedule: 10 dispatch points per day"
    echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
    echo "  ✓ State: ~/.local/state/exocortex/"
    echo "  ✓ Logs: ~/logs/synchronizer/systemd-scheduler.log"
    echo ""
    echo "Verify: systemctl --user list-timers | grep exocortex"
    echo "Status: bash $SCHEDULER_SH status"
    echo "Logs:   journalctl --user -u exocortex-scheduler.service -f"
    echo ""
    echo "Auto-start without login session (recommended):"
    echo "  loginctl enable-linger \$USER"
    echo ""
    echo "Uninstall:"
    echo "  systemctl --user disable --now exocortex-scheduler.timer"
    echo "  rm $SYSTEMD_DIR/exocortex-scheduler.{service,timer}"
    echo "  systemctl --user daemon-reload"
fi

echo ""
echo "Telegram (optional): create ~/.config/aist/env with:"
echo "  export TELEGRAM_BOT_TOKEN=\"your-token\""
echo "  export TELEGRAM_CHAT_ID=\"your-id\""
