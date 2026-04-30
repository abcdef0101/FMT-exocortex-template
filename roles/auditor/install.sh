#!/bin/bash
# Install Auditor role
# On-demand only — no scheduled jobs (launchd/systemd не нужны)
set -euo pipefail

# === Named parameters ===
WORKSPACE_DIR=""
ROOT_DIR=""
AGENT_AI_PATH=""

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
  *)
    echo "Неизвестный аргумент: $1" >&2
    exit 1
    ;;
  esac
done

missing=()
[ -z "$WORKSPACE_DIR" ] && missing+=("--workspace-dir")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Ошибка: обязательные параметры не указаны:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "Ошибка: WORKSPACE_DIR не существует: $WORKSPACE_DIR" >&2
  exit 1
fi

if [ -n "$ROOT_DIR" ] && [ ! -d "$ROOT_DIR" ]; then
  echo "Ошибка: ROOT_DIR не существует: $ROOT_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Auditor Agent..."

chmod +x "$SCRIPT_DIR/scripts/auditor.sh"

mkdir -p "$WORKSPACE_DIR/logs/auditor"

echo ""
echo "Done. Auditor installed (on-demand, no scheduled jobs)."
echo ""
echo "Usage:"
echo "  auditor.sh ... audit-plan-consistency   — кросс-контекстная проверка планов (Day Open)"
echo "  auditor.sh ... audit-coverage           — аудит покрытия source→target"
echo "  auditor.sh ... on-demand                — аудит по запросу"
echo ""
echo "Prompts: $SCRIPT_DIR/prompts/"
