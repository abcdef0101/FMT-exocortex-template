#!/bin/bash
# Synchronizer: установка центрального диспетчера
# Targets: macOS (launchd), Linux (systemd user timer)
# Заменяет отдельные агенты Стратега единым scheduler
set -euo pipefail

# === Named parameters ===
WORKSPACE_DIR=""
TIMEZONE_HOUR=""
NAMESPACE=""

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
  --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  *)
    echo "Неизвестный аргумент: $1" >&2
    exit 1
    ;;
  esac
done

missing=()
[ -z "$WORKSPACE_DIR" ] && missing+=("--workspace-dir")
[ -z "$TIMEZONE_HOUR" ] && missing+=("--timezone-hour")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Ошибка: обязательные параметры не указаны:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
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

# Default namespace = workspace directory name, sanitised
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="$(basename "$WORKSPACE_DIR" | tr -c '[:alnum:]._-' '-')"
fi

LAUNCHD_SRC="$SCRIPT_DIR/scripts/launchd"
SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"

echo "Installing Synchronizer (central scheduler)..."

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

# Создаём директории состояния
mkdir -p "$WORKSPACE_DIR/state"
mkdir -p "$WORKSPACE_DIR/logs/synchronizer"

if [[ "$OSTYPE" == "darwin"* ]]; then
  # === macOS: launchd ===
  TARGET_DIR="$HOME/Library/LaunchAgents"

  # Unload old agent if present
  launchctl unload "$TARGET_DIR/com.exocortex.scheduler.plist" 2>/dev/null || true

  # Выгружаем также все legacy Стратег-агенты (по маске)
  for plist in "$TARGET_DIR"/com.strategist.*; do
    [ -f "$plist" ] || continue
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
  done

  # Copy plist with placeholder substitution + namespaced filename
  basename_plist="com.exocortex.scheduler.${NAMESPACE}.plist"
  sed \
    -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" \
    -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
    -e "s|{{ROLES_DIR}}|$ROLES_DIR|g" \
    -e "s|{{ENV_FILE}}|$ENV_FILE|g" \
    -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
    -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
    "$LAUNCHD_SRC/com.exocortex.scheduler.plist" >"$TARGET_DIR/$basename_plist"

  launchctl load "$TARGET_DIR/$basename_plist"

  echo "Done. Agent loaded:"
  launchctl list | grep "scheduler.${NAMESPACE}" || true
else
  # === Linux: systemd user timer ===
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"

  # Copy service/timer files with placeholder substitution + namespace in filename
  for unit in "$SYSTEMD_SRC"/*.{service,timer}; do
    [ -f "$unit" ] || continue
    basename_unit="$(basename "$unit" | sed "s|\(\.service\|\.timer\)$|-${NAMESPACE}\1|")"
    sed \
      -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" \
      -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
      -e "s|{{ROLES_DIR}}|$ROLES_DIR|g" \
      -e "s|{{ENV_FILE}}|$ENV_FILE|g" \
      -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
      -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
      -e "s|{{HOME}}|$HOME|g" \
      "$unit" >"$SYSTEMD_DIR/$basename_unit"
  done

  systemctl --user daemon-reload
  systemctl --user enable --now "exocortex-scheduler-${NAMESPACE}.timer"

  echo "Done. Timer installed:"
  systemctl --user list-timers | grep "exocortex-scheduler-${NAMESPACE}" || true
fi

echo "  ✓ Schedule: 10 dispatch points per day"
echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
echo "  ✓ State: $WORKSPACE_DIR/state/"
echo "  ✓ Logs: $WORKSPACE_DIR/logs/synchronizer/"
echo ""
echo "Status: bash $SCRIPT_DIR/scripts/scheduler.sh --workspace-dir $WORKSPACE_DIR --roles-dir $ROLES_DIR --env-file $ENV_FILE status"
echo ""

if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Auto-wake (recommended): plan ready before you wake up"
  echo "  sudo pmset repeat wakeorpoweron MTWRFSU 03:55:00"
  echo "  sudo pmset -b sleep 0 && sudo pmset -b standby 0"
  echo "  (Cancel: sudo pmset repeat cancel)"
else
  echo "Auto-wake on Linux: systemd timer with WakeSystem=true or rtcwake"
fi
echo ""
echo "Telegram (optional): create ~/.config/aist/env with:"
echo "  export TELEGRAM_BOT_TOKEN=\"your-token\""
echo "  export TELEGRAM_CHAT_ID=\"your-id\""
echo ""
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Uninstall: launchctl unload $TARGET_DIR/com.exocortex.scheduler.${NAMESPACE}.plist && rm $TARGET_DIR/com.exocortex.scheduler.${NAMESPACE}.plist"
else
  echo "Uninstall: systemctl --user disable --now exocortex-scheduler-${NAMESPACE}.timer && rm ~/.config/systemd/user/exocortex-scheduler-${NAMESPACE}.{service,timer} && systemctl --user daemon-reload"
fi
