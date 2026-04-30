#!/bin/bash
# Extractor: установка агента inbox-check
# Targets: macOS (launchd), Linux (systemd user timer)
set -euo pipefail

# === Named parameters ===
WORKSPACE_DIR=""
ROOT_DIR=""
AGENT_AI_PATH=""
NAMESPACE=""

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
  --agent-ai-path)
    AGENT_AI_PATH="$2"
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
[ -z "$ROOT_DIR" ] && missing+=("--root-dir")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Ошибка: обязательные параметры не указаны:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
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

# Default agent AI path = auto-detect claude
if [ -z "$AGENT_AI_PATH" ]; then
  AGENT_AI_PATH="$(command -v claude 2>/dev/null || echo claude)"
fi

# Default namespace = workspace directory name, sanitised
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="$(basename "$WORKSPACE_DIR" | tr -c '[:alnum:]._-' '-')"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/scripts/launchd"
SYSTEMD_SRC="$SCRIPT_DIR/scripts/systemd"
CLAUDE_PATH="$AGENT_AI_PATH"

echo "Installing Extractor Agent..."

# Make scripts executable
chmod +x "$SCRIPT_DIR/scripts/extractor.sh"

# Create log directory in workspace
mkdir -p "$WORKSPACE_DIR/logs/extractor"

if [[ "$OSTYPE" == "darwin"* ]]; then
  # === macOS: launchd ===
  TARGET_DIR="$HOME/Library/LaunchAgents"

  # Unload old agent if present
  launchctl unload "$TARGET_DIR/com.extractor.inbox-check.plist" 2>/dev/null || true

  # Copy plist with placeholder substitution + namespaced filename
  basename_plist="com.extractor.${NAMESPACE}.inbox-check.plist"
  sed \
    -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" \
    -e "s|{{WORKSPACE_DIR}}|$WORKSPACE_DIR|g" \
    -e "s|{{CLAUDE_PATH}}|$CLAUDE_PATH|g" \
    -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
    "$LAUNCHD_DIR/com.extractor.inbox-check.plist" >"$TARGET_DIR/$basename_plist"

  # Load agent
  launchctl load "$TARGET_DIR/$basename_plist"

  echo "Done. Agent loaded:"
  launchctl list | grep "com.extractor.${NAMESPACE}" || true
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
      -e "s|{{CLAUDE_PATH}}|$CLAUDE_PATH|g" \
      -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
      -e "s|{{HOME}}|$HOME|g" \
      "$unit" >"$SYSTEMD_DIR/$basename_unit"
  done

  systemctl --user daemon-reload
  systemctl --user enable --now "exocortex-extractor-${NAMESPACE}.timer"

  echo "Done. Timer installed:"
  systemctl --user list-timers | grep "exocortex-extractor-${NAMESPACE}" || true
fi
