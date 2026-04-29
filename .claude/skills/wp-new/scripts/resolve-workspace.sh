# resolve-workspace.sh — общая библиотека резолва FMT root и workspace.
# Library-Class: source-pure
#
# Source-файл: source "$(dirname "$0")/resolve-workspace.sh"
# После source доступны:
#   resolve_fmt_dir      — ищет FMT root вверх от $0 (или CWD) по маркерам
#   resolve_workspace    — читает CURRENT_WORKSPACE symlink (или CLI override)
#   FMT_DIR              — корень FMT-репозитория (set by resolve_fmt_dir)
#   WORKSPACE_DIR        — путь к текущему workspace (set by resolve_workspace)
#   WORKSPACE_MEMORY     — путь к memory/ внутри workspace
#
# NOTE: strict mode is the caller's responsibility (entry-point pattern).
#
# Скрипты-потребители должны определить:
#   err()  — функция вывода ошибок (если нужна своя)
#   CLI_WORKSPACE_DIR — если скрипт принимает --workspace-dir

[[ -n "${_LIB_RESOLVE_WORKSPACE_LOADED:-}" ]] && return 0
readonly _LIB_RESOLVE_WORKSPACE_LOADED=1

if ! declare -f _rw_err >/dev/null 2>&1; then
  _rw_err() { echo "ERROR: $*" >&2; }
  _rw_warn() { echo "WARN: $*" >&2; }
fi

resolve_fmt_dir() {
  local dir
  dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || dir=""
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    dir="$(pwd)"
  fi
  local prev=""
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/update-manifest.json" ] || [ -d "$dir/workspaces" ]; then
      FMT_DIR="$dir"
      return 0
    fi
    prev="$dir"
    dir="$(dirname "$dir")"
    if [ "$dir" = "$prev" ]; then
      break
    fi
  done
  _rw_err "Cannot find FMT repo root (no update-manifest.json or workspaces/ found)"
  return 1
}

resolve_workspace() {
  WORKSPACE_MEMORY=""
  WORKSPACE_DIR=""

  if [ -n "${CLI_WORKSPACE_DIR:-}" ]; then
    resolve_workspace_from_path "$CLI_WORKSPACE_DIR"
  else
    resolve_workspace_from_symlink
  fi
}

resolve_workspace_from_path() {
  local ws_dir="$1"
  if [ ! -d "$ws_dir" ]; then
    _rw_err "Workspace directory not found: $ws_dir"
    return 1
  fi
  if [ ! -d "$ws_dir/memory" ]; then
    _rw_err "Invalid workspace (no memory/ subdir): $ws_dir"
    return 1
  fi
  WORKSPACE_DIR="$ws_dir"
  WORKSPACE_MEMORY="$ws_dir/memory"
}

resolve_workspace_from_symlink() {
  local ws_link="$FMT_DIR/workspaces/CURRENT_WORKSPACE"
  if [ ! -L "$ws_link" ]; then
    _rw_warn "workspace symlink not found: $ws_link"
    return 1
  fi
  local ws_target
  ws_target="$(cd "$(dirname "$ws_link")" 2>/dev/null && cd "$(readlink "$ws_link")" 2>/dev/null && pwd)" || ws_target=""
  if [ -z "$ws_target" ]; then
    _rw_warn "Cannot resolve workspace symlink target: $ws_link"
    return 1
  fi
  local ws_dir=""
  if [ -d "$FMT_DIR/workspaces/$ws_target" ]; then
    ws_dir="$FMT_DIR/workspaces/$ws_target"
  elif [ -d "$ws_target" ]; then
    ws_dir="$ws_target"
  fi
  if [ -n "$ws_dir" ]; then
    WORKSPACE_DIR="$ws_dir"
    if [ -d "$ws_dir/memory" ]; then
      WORKSPACE_MEMORY="$ws_dir/memory"
    fi
  fi
}
