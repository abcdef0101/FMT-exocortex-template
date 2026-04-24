#!/bin/bash
# Install Strategist Agent launchd jobs
set -e

# === Named parameters ===
WORKSPACE_DIR=""
CLAUDE_PATH=""
TIMEZONE_HOUR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --workspace-dir)
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  --claude-path)
    CLAUDE_PATH="$2"
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

missing=()
[ -z "$WORKSPACE_DIR" ] && missing+=("--workspace-dir")
[ -z "$CLAUDE_PATH" ] && missing+=("--claude-path")
[ -z "$TIMEZONE_HOUR" ] && missing+=("--timezone-hour")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Ошибка: обязательные параметры не указаны:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

files=(
  "$WORKSPACE_DIR"
)
for f in "${files[@]}"; do
  if [ ! -d "$f" ]; then
    echo "Ошибка: директория не существует: $f" >&2
    exit 1
  fi
done

if ! command -v "$CLAUDE_PATH" &>/dev/null; then
  echo "Ошибка: claude не найден по пути: $CLAUDE_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/scripts/launchd"
TARGET_DIR="$HOME/Library/LaunchAgents"

echo "Installing Strategist Agent launchd jobs..."

# Unload old agents if present
launchctl unload "$TARGET_DIR/com.strategist.morning.plist" 2>/dev/null || true
launchctl unload "$TARGET_DIR/com.strategist.weekreview.plist" 2>/dev/null || true

# Copy plist files with placeholder substitution
for plist in "$LAUNCHD_DIR"/*.plist; do
  basename_plist="$(basename "$plist")"
  sed \
    -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
    -e "s|{{CLAUDE_PATH}}|$CLAUDE_PATH|g" \
    -e "s|{{TIMEZONE_HOUR}}|$TIMEZONE_HOUR|g" \
    "$plist" >"$TARGET_DIR/$basename_plist"
done

# Make script executable
chmod +x "$SCRIPT_DIR/scripts/strategist.sh"

# Load agents
launchctl load "$TARGET_DIR/com.strategist.morning.plist"
launchctl load "$TARGET_DIR/com.strategist.weekreview.plist"

echo "Done. Agents loaded:"
launchctl list | grep strategist
