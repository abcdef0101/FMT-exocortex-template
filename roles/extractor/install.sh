#!/bin/bash
# Extractor: установка launchd-агента для inbox-check
# Запускает inbox-check каждые 3 часа
set -e

# === Named parameters ===
WORKSPACE_DIR=""
ROOT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --workspace-dir)
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  --root-dir)
    ROOT_DIR="$2"
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
[ -z "$ROOT_DIR" ] && MISSING+=("--root-dir")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Ошибка: обязательные параметры: ${MISSING[*]}" >&2
  echo "Usage: bash install.sh --workspace-dir /path/to/workspace --root-dir /path/to/root" >&2
  exit 1
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "Ошибка: WORKSPACE_DIR не существует: $WORKSPACE_DIR" >&2
  exit 1
fi

if [ ! -d "$ROOT_DIR" ]; then
  echo "Ошибка: ROOT_DIR не существует: $ROOT_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_DIR="$ROOT_DIR/roles"
CLAUDE_PATH="$(command -v claude 2>/dev/null || echo claude)"
ENV_FILE="$WORKSPACE_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Ошибка: ENV_FILE не существует: $ENV_FILE" >&2
  exit 1
fi

PLIST_SRC="$SCRIPT_DIR/scripts/launchd/com.extractor.inbox-check.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.extractor.inbox-check.plist"

echo "Installing Extractor launchd agent..."

if [ ! -f "$PLIST_SRC" ]; then
  echo "ERROR: $PLIST_SRC not found"
  exit 1
fi

chmod +x "$SCRIPT_DIR/scripts/extractor.sh"

launchctl unload "$PLIST_DST" 2>/dev/null || true

mkdir -p "$WORKSPACE_DIR/logs/extractor"

sed \
  -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" \
  -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
  -e "s|{{ROLES_DIR}}|$ROLES_DIR|g" \
  -e "s|{{CLAUDE_PATH}}|$CLAUDE_PATH|g" \
  "$PLIST_SRC" >"$PLIST_DST"

launchctl load "$PLIST_DST"

echo "  ✓ Installed: com.extractor.inbox-check"
echo "  ✓ Interval: every 3 hours"
echo "  ✓ Logs: $WORKSPACE_DIR/logs/extractor/"
echo ""
echo "Verify: launchctl list | grep extractor"
echo "Uninstall: launchctl unload $PLIST_DST && rm $PLIST_DST"
