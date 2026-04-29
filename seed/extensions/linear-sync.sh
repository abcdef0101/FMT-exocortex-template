#!/usr/bin/env bash
# linear-sync.sh — Extension: синхронизация с Linear (day-close шаг 4b)
#
# Вызывается из day-close/SKILL.md после day-close.sh.
# Читает params.yaml → linear_sync_path и вызывает внешний скрипт.
#
# Использование:
#   linear-sync.sh --workspace-dir DIR
#
# Exit codes: 0=success/skip, 1=error

set -euo pipefail

WORKSPACE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
  --workspace-dir)
    if [ $# -lt 2 ]; then
      echo "linear-sync: --workspace-dir requires an argument" >&2
      exit 1
    fi
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  *)
    echo "linear-sync: unknown argument: $1" >&2
    exit 1
    ;;
  esac
done

if [ -z "$WORKSPACE_DIR" ]; then
  echo "linear-sync: --workspace-dir is required" >&2
  exit 1
fi

PARAMS_YAML="$WORKSPACE_DIR/params.yaml"
if [ ! -f "$PARAMS_YAML" ]; then
  exit 0
fi

LINEAR_SYNC_PATH=""
raw=$(python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')); print(d.get('linear_sync_path',''))" "$PARAMS_YAML" 2>/dev/null || echo "")
if [ -n "$raw" ]; then
  LINEAR_SYNC_PATH="${raw/#\~/$HOME}"
fi

if [ -z "$LINEAR_SYNC_PATH" ]; then
  exit 0
fi

if [ ! -x "$LINEAR_SYNC_PATH" ]; then
  echo "linear-sync: script not found or not executable: $LINEAR_SYNC_PATH" >&2
  exit 0
fi

"$LINEAR_SYNC_PATH" --workspace-dir "$WORKSPACE_DIR"
