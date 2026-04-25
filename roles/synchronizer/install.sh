#!/bin/bash
# Synchronizer: установка центрального диспетчера (launchd)
# Заменяет отдельные launchd-агенты Стратега единым scheduler
set -e

# === Named parameters ===
WORKSPACE_DIR=""
TIMEZONE_HOUR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --workspace-dir)
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  --timezone-hour)
    TIMEZONE_HOUR="$2"
    shift 2
    ;;
  *)
    echo "Неизвестный аргумент: $1" >&2
    exit 1
    ;;
  esac
done

MISSING=()
[ -z "$WORKSPACE_DIR" ] && MISSING+=("--workspace-dir")
[ -z "$TIMEZONE_HOUR" ] && MISSING+=("--timezone-hour")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Ошибка: обязательные параметры: ${MISSING[*]}" >&2
  echo "Usage: bash install.sh --workspace-dir /path/to/workspace --timezone-hour 4" >&2
  exit 1
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "Ошибка: WORKSPACE_DIR не существует: $WORKSPACE_DIR" >&2
  exit 1
fi

if ! [[ "$TIMEZONE_HOUR" =~ ^[0-9]+$ ]] || [ "$TIMEZONE_HOUR" -lt 0 ] || [ "$TIMEZONE_HOUR" -gt 23 ]; then
  echo "Ошибка: --timezone-hour должен быть числом 0..23, got: $TIMEZONE_HOUR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ROLES_DIR="$ROOT_DIR/roles"
ENV_FILE="$WORKSPACE_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Ошибка: ENV_FILE не существует: $ENV_FILE" >&2
  exit 1
fi
PLIST_SRC="$SCRIPT_DIR/scripts/launchd/com.exocortex.scheduler.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.exocortex.scheduler.plist"

echo "Installing Synchronizer (central scheduler)..."

if [ ! -f "$PLIST_SRC" ]; then
  echo "ERROR: $PLIST_SRC not found"
  exit 1
fi

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

# Выгружаем старые агенты
launchctl unload "$PLIST_DST" 2>/dev/null || true
# Выгружаем также legacy Стратег-агенты (если были)
launchctl unload "$HOME/Library/LaunchAgents/com.strategist.morning.plist" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/com.strategist.weekreview.plist" 2>/dev/null || true

# Создаём директории состояния
mkdir -p "$WORKSPACE_DIR/state"
mkdir -p "$WORKSPACE_DIR/logs/synchronizer"

# Рендерим plist с подстановкой placeholder'ов
sed \
  -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" \
  -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
  -e "s|{{ROLES_DIR}}|$ROLES_DIR|g" \
  -e "s|{{ENV_FILE}}|$ENV_FILE|g" \
  -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
  "$PLIST_SRC" > "$PLIST_DST"

launchctl load "$PLIST_DST"

echo "  ✓ Installed: com.exocortex.scheduler"
echo "  ✓ Schedule: 10 dispatch points per day"
echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
echo "  ✓ State: $WORKSPACE_DIR/state/"
echo "  ✓ Logs: $WORKSPACE_DIR/logs/synchronizer/"
echo ""
echo "Verify: launchctl list | grep exocortex"
echo "Status: bash $SCRIPT_DIR/scripts/scheduler.sh --workspace-dir $WORKSPACE_DIR --roles-dir $ROLES_DIR --env-file $ENV_FILE status"
echo ""
echo "Auto-wake (recommended): plan ready before you wake up"
if [[ "$(uname)" == "Darwin" ]]; then
  echo "  sudo pmset repeat wakeorpoweron MTWRFSU 03:55:00"
  echo "  sudo pmset -b sleep 0 && sudo pmset -b standby 0  # laptop: prevent sleep on battery profile"
  echo "  (Cancel: sudo pmset repeat cancel)"
else
  echo "  Linux: sudo rtcwake or systemd timer with WakeSystem=true"
  echo "  See docs/SETUP-GUIDE.md for details"
fi
echo ""
echo "Telegram (optional): create ~/.config/aist/env with:"
echo "  export TELEGRAM_BOT_TOKEN=\"your-token\""
echo "  export TELEGRAM_CHAT_ID=\"your-id\""
echo ""
echo "Uninstall: launchctl unload $PLIST_DST && rm $PLIST_DST"
