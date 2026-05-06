#!/bin/bash
# Install Strategist Agent jobs
# Targets: macOS (launchd), Linux (systemd user timers)
set -euo pipefail

# === Named parameters ===
WORKSPACE_DIR=""
AI_CLI_PATH="${AI_CLI_PATH:-${CLAUDE_PATH:-}}"
TIMEZONE_HOUR=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --workspace-dir)
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  --claude-path|--ai-cli-path)
    AI_CLI_PATH="$2"
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
[ -z "$AI_CLI_PATH" ] && missing+=("--ai-cli-path (or --claude-path)")
[ -z "$TIMEZONE_HOUR" ] && missing+=("--timezone-hour")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Ошибка: обязательные параметры не указаны:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

for f in "$WORKSPACE_DIR"; do
  if [ ! -d "$f" ]; then
    echo "Ошибка: директория не существует: $f" >&2
    exit 1
  fi
done

if ! command -v "$AI_CLI_PATH" &>/dev/null; then
  echo "Ошибка: AI CLI не найден по пути: $AI_CLI_PATH" >&2
  exit 1
fi

# Default namespace = workspace directory name, sanitised
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="$(basename "$WORKSPACE_DIR" | tr -c '[:alnum:]._-' '-')"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/scripts/launchd"
SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"

echo "Installing Strategist Agent..."

# Make scripts executable
chmod +x "$SCRIPT_DIR/scripts/strategist.sh"

# Create log directory in workspace
mkdir -p "$WORKSPACE_DIR/logs/strategist"

if [[ "$OSTYPE" == "darwin"* ]]; then
  # === macOS: launchd ===
  TARGET_DIR="$HOME/Library/LaunchAgents"

  # Unload old agents if present
  launchctl unload "$TARGET_DIR/com.strategist.morning.plist" 2>/dev/null || true
  launchctl unload "$TARGET_DIR/com.strategist.weekreview.plist" 2>/dev/null || true

  # Copy plist files with placeholder substitution
  for plist in "$LAUNCHD_DIR"/*.plist; do
    basename_plist="$(basename "$plist" | sed "s/\.plist$/\.${NAMESPACE}\.plist/")"
    sed \
      -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
      -e "s|{{CLAUDE_PATH}}|$AI_CLI_PATH|g" \
      -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
      -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
      "$plist" >"$TARGET_DIR/$basename_plist"
  done

  # Load agents
  launchctl load "$TARGET_DIR/com.strategist.${NAMESPACE}.morning.plist"
  launchctl load "$TARGET_DIR/com.strategist.${NAMESPACE}.weekreview.plist"



# Linux: systemd user timers
elif systemctl --user 2>/dev/null; then
  SYSTEMD_DIR="$SCRIPT_DIR/systemd"
  TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/systemd/user"
  mkdir -p "$TARGET_DIR"

  for unit in "$SYSTEMD_DIR"/*.service; do
    basename_unit="$(basename "$unit" | sed "s/\.service$/\.${NAMESPACE}\.service/")"
    sed \
      -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
      -e "s|{{CLAUDE_PATH}}|$AI_CLI_PATH|g" \
      -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
      -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
      -e "s|{{HOME}}|$HOME|g" \
      "$unit" >"$SYSTEMD_DIR/$basename_unit"
  done

  systemctl --user daemon-reload
  systemctl --user enable --now exocortex-strategist-morning.timer
  systemctl --user enable --now exocortex-strategist-weekreview.timer

  echo "Done. Timers installed:"
  systemctl --user list-timers | grep exocortex-strategist || true
fi
