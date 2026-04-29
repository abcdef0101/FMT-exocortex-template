#!/usr/bin/env bash
# Использование:
#   bash .claude/skills/iwe-workspace/workspace.sh --get-workspaces
#   bash .claude/skills/iwe-workspace/workspace.sh --get-current
#   bash .claude/skills/iwe-workspace/workspace.sh --set-workspace=<name>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

list_workspaces() {
  local ws_dir="$ROOT/workspaces"
  if [ ! -d "$ws_dir" ]; then
    echo "ERROR: $ws_dir не существует" >&2
    exit 1
  fi
  for d in "$ws_dir"/*/; do
    [ -d "$d" ] && [ ! -L "${d%/}" ] || continue
    basename "$d"
  done
}

set_workspace() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "ERROR: --set-workspace name is required." >&2
    exit 1
  fi
  if ! echo "$name" | grep -qxE '[a-zA-Z0-9][a-zA-Z0-9._-]*'; then
    echo "ERROR: '$name' is invalid. Use letters, digits, hyphens, dots, underscores; must start with a letter or digit." >&2
    exit 1
  fi
  local target=${ROOT}"/workspaces/"${name}
  if [ ! -d "$target" ]; then
    echo "ERROR: Directory does not exist: $target"
    exit 1
  fi
  ln -sfn "$target" "$ROOT/workspaces/CURRENT_WORKSPACE"
  echo "Workspace установлен: $name"
}

get_current() {
  local link="$ROOT/workspaces/CURRENT_WORKSPACE"
  if [ ! -L "$link" ]; then
    echo "(не установлено)"
    exit 0
  fi
  readlink "$link" | xargs basename
}

for arg in "$@"; do
  case "$arg" in
  --get-workspaces)
    list_workspaces
    exit 0
    ;;
  --get-current)
    get_current
    exit 0
    ;;
  --set-workspace=*)
    set_workspace "${arg#--set-workspace=}"
    exit 0
    ;;
  esac
done

echo "Usage: $0 <--get-workspaces|--get-current|--set-workspace=<name>>" >&2
exit 1
