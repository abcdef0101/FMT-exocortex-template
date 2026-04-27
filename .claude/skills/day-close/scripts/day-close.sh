#!/usr/bin/env bash
# day-close.sh — Механические шаги Day Close (backup + reindex)
#
# Вызывается из .claude/skills/day-close/SKILL.md (шаг 4).
# НЕ содержит бизнес-логику Day Close — только механические операции.
#
# Backup: копирует workspace memory/ (MEMORY.md, day-rhythm-config.yaml, etc.)
# в DS-strategy/exocortex/. Symlinks (persistent-memory) пропускаются.
#
# Использование:
#   day-close.sh              # оба шага
#   day-close.sh --backup     # только backup
#   day-close.sh --reindex    # только reindex
#
# Вызов из SKILL.md: bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh"
#
# Конфигурация через env vars:
#   WORKSPACE_DIR             — корень workspace (default: через CURRENT_WORKSPACE symlink)
#   IWE_SELECTIVE_REINDEX     — путь к selective-reindex.sh
#   IWE_SOURCES_JSON          — путь к sources.json
#   IWE_SOURCES_PERSONAL_JSON — путь к sources-personal.json
#   IWE_DAY_CLOSE_LOG         — путь к log-файлу
#   GIT_MEMORY_BACKUP          — push memory files to workspace git repo (default: true)
#
# Exit codes: 0=success, 1=error/bad-arg

set -euo pipefail

# globals (set by resolve_paths / resolve_config, read by do_*)
FMT_DIR=""
WORKSPACE_MEMORY=""
WORKSPACE_DIR=""
CLI_WORKSPACE_DIR=""
GIT_MEMORY_BACKUP=""
DS_STRATEGY=""
EXOCORTEX_DST=""
SELECTIVE_REINDEX=""
SOURCES_JSON=""
SOURCES_PERSONAL_JSON=""
PARAMS_YAML=""
LOG_FILE=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[day-close]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[day-close]${NC} $1" >&2; }
err() { echo -e "${RED}[day-close]${NC} $1" >&2; }

show_usage() {
  echo "Использование: day-close.sh [--backup] [--reindex] [--workspace-dir DIR]"
  echo "  Без аргументов — оба шага, workspace из CURRENT_WORKSPACE symlink"
  echo "  --workspace-dir DIR — использовать указанный workspace (проверяет наличие memory/)"
}

load_env() {
  local env_file="$WORKSPACE_DIR/.env"
  if [ -f "$env_file" ]; then
    while IFS='=' read -r key value; do
      value="${value#\"}"
      value="${value%\"}"
      case "$key" in
      GIT_MEMORY_BACKUP) GIT_MEMORY_BACKUP="$value" ;;
      esac
    done <"$env_file"
  fi
  GIT_MEMORY_BACKUP="${GIT_MEMORY_BACKUP:-true}"
}

resolve_fmt_dir() {
  local dir
  dir="$(cd "$(dirname "$0")" && pwd)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    err "Cannot resolve script directory from \$0=$0"
    exit 1
  fi
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/update-manifest.json" ] || [ -d "$dir/workspaces" ]; then
      FMT_DIR="$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  err "Cannot find FMT repo root (no update-manifest.json or workspaces/ found)"
  exit 1
}

resolve_workspace() {
  WORKSPACE_MEMORY=""
  WORKSPACE_DIR=""

  if [ -n "$CLI_WORKSPACE_DIR" ]; then
    resolve_workspace_from_path "$CLI_WORKSPACE_DIR"
  else
    resolve_workspace_from_symlink
  fi
}

resolve_workspace_from_path() {
  local ws_dir="$1"
  if [ ! -d "$ws_dir" ]; then
    err "Workspace directory not found: $ws_dir"
    exit 1
  fi
  if [ ! -d "$ws_dir/memory" ]; then
    err "Invalid workspace (no memory/ subdir): $ws_dir"
    exit 1
  fi
  WORKSPACE_DIR="$ws_dir"
  WORKSPACE_MEMORY="$ws_dir/memory"
}

resolve_workspace_from_symlink() {
  local ws_link="$FMT_DIR/workspaces/CURRENT_WORKSPACE"
  if [ ! -L "$ws_link" ]; then
    warn "  workspace symlink not found: $ws_link"
    return
  fi
  local ws_target
  ws_target="$(cd "$(dirname "$ws_link")" 2>/dev/null && cd "$(readlink "$ws_link")" 2>/dev/null && pwd)" || ws_target=""
  if [ -z "$ws_target" ]; then
    warn "  Cannot resolve workspace symlink target: $ws_link"
    return
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

resolve_config() {
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
  EXOCORTEX_DST="$DS_STRATEGY/exocortex"

  SELECTIVE_REINDEX="${IWE_SELECTIVE_REINDEX:-$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/selective-reindex.sh}"
  SOURCES_JSON="${IWE_SOURCES_JSON:-$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/sources.json}"
  SOURCES_PERSONAL_JSON="${IWE_SOURCES_PERSONAL_JSON:-$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/sources-personal.json}"
  PARAMS_YAML="$WORKSPACE_DIR/params.yaml"
  LOG_FILE="${IWE_DAY_CLOSE_LOG:-$WORKSPACE_DIR/DS-agent-workspace/scheduler/day-close.log}"
}

resolve_paths() {
  resolve_fmt_dir
  resolve_workspace
  resolve_config
}

do_backup() {
  log "Шаг 1/2: Backup workspace memory/ → exocortex/"

  mkdir -p "$EXOCORTEX_DST"

  local count=0

  if [ -d "$WORKSPACE_MEMORY" ]; then
    for f in "$WORKSPACE_MEMORY"/*; do
      [ -f "$f" ] || continue
      local bname
      bname=$(basename "$f")
      case "$bname" in
      *.md | *.yaml | *.yml | *.json) ;;
      *) continue ;;
      esac
      cp "$f" "$EXOCORTEX_DST/"
      count=$((count + 1))
    done
  else
    warn "  workspace memory/ not found: $WORKSPACE_MEMORY"
  fi

  if [ -f "$WORKSPACE_DIR/CLAUDE.md" ]; then
    cp "$WORKSPACE_DIR/CLAUDE.md" "$EXOCORTEX_DST/CLAUDE.md"
    count=$((count + 1))
  fi

  log "  Скопировано: $count файлов → $EXOCORTEX_DST/"
}

do_git_backup() {
  if [ "$GIT_MEMORY_BACKUP" != "true" ]; then
    log "  GIT_MEMORY_BACKUP=$GIT_MEMORY_BACKUP — git backup пропущен"
    return 0
  fi

  local ws_git="$WORKSPACE_DIR"
  if [ ! -d "$ws_git/.git" ]; then
    warn "  workspace не является git-репозиторием: $ws_git — git backup пропущен"
    return 0
  fi

  local memory_dir="$WORKSPACE_DIR/memory"
  local files_to_commit=()
  local f
  for f in "$memory_dir/MEMORY.md" "$memory_dir/day-rhythm-config.yaml" "$WORKSPACE_DIR/CLAUDE.md"; do
    if [ -f "$f" ]; then
      files_to_commit+=("$f")
    fi
  done

  if [ ${#files_to_commit[@]} -eq 0 ]; then
    log "  Нет файлов для git backup"
    return 0
  fi

  git -C "$ws_git" add "${files_to_commit[@]}" 2>&1 || {
    warn "  git add failed"
    return 1
  }

  if git -C "$ws_git" diff --cached --quiet 2>/dev/null; then
    log "  Git backup: нет изменений для коммита"
    return 0
  fi

  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  git -C "$ws_git" commit -m "backup: memory files ($date_str)" 2>&1 || {
    warn "  git commit failed"
    return 1
  }

  if git -C "$ws_git" remote get-url origin >/dev/null 2>&1; then
    git -C "$ws_git" push origin HEAD 2>&1 || {
      warn "  git push failed (commit сохранён локально)"
      return 0
    }
    log "  Git backup: commit + push выполнен (${#files_to_commit[@]} файлов)"
  else
    log "  Git backup: commit выполнен (no remote, push skipped)"
  fi
}

do_reindex() {
  log "Шаг 2/2: Knowledge-MCP reindex"

  if [ ! -x "$SELECTIVE_REINDEX" ]; then
    warn "  selective-reindex.sh не найден: $SELECTIVE_REINDEX — пропуск"
    return 0
  fi

  local dir_map
  dir_map=$(
    python3 - "$SOURCES_JSON" "$SOURCES_PERSONAL_JSON" <<'PYEOF'
import sys, json, os
for config_path in sys.argv[1:]:
    if not os.path.exists(config_path):
        continue
    for s in json.load(open(config_path, encoding='utf-8')):
        resolved = os.path.expanduser(s["path"])
        while not os.path.isdir(os.path.join(resolved, ".git")) and resolved != "/":
            resolved = os.path.dirname(resolved)
        if resolved == "/":
            continue
        print(f"{os.path.basename(resolved)}\t{s['source']}\t{config_path}")
PYEOF
  ) || {
    warn "  Mapping build failed — пропуск reindex"
    return 0
  }

  local l2_sources="" l4_sources=""
  for repo in "$WORKSPACE_DIR"/PACK-* "$WORKSPACE_DIR"/DS-*; do
    [ -d "$repo/.git" ] || continue
    local repo_name
    repo_name=$(basename "$repo")
    local today_commits
    today_commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>&1 | wc -l | tr -d ' ') || continue
    if [ "$today_commits" -gt 0 ]; then
      local match
      match=$(echo "$dir_map" | awk -F'\t' -v d="$repo_name" '$1==d {print $2"\t"$3; exit}')
      if [ -n "$match" ]; then
        local src cfg
        src=$(echo "$match" | cut -f1)
        cfg=$(echo "$match" | cut -f2)
        if [ "$cfg" = "$SOURCES_JSON" ]; then
          l2_sources="$l2_sources $src"
        else
          l4_sources="$l4_sources $src"
        fi
      else
        log "  ⚠ $repo_name: не в sources — пропуск"
      fi
    fi
  done

  if [ -z "$l2_sources" ] && [ -z "$l4_sources" ]; then
    log "  Нет изменений в индексируемых источниках — пропуск reindex"
    return 0
  fi

  if [ -n "$l2_sources" ]; then
    log "  L2 источники:$l2_sources"
    # shellcheck disable=SC2086
    "$SELECTIVE_REINDEX" $l2_sources
  fi

  if [ -n "$l4_sources" ]; then
    log "  L4 источники:$l4_sources"
    # shellcheck disable=SC2086
    SOURCES_CONFIG="$SOURCES_PERSONAL_JSON" "$SELECTIVE_REINDEX" $l4_sources
  fi
}

write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | day-close | backup=$1 reindex=$2" >>"$LOG_FILE"
}

main() {
  local do_all=true
  local run_backup=false
  local run_reindex=false

  CLI_WORKSPACE_DIR=""

  while [ $# -gt 0 ]; do
    case "$1" in
    --backup)
      run_backup=true
      do_all=false
      shift
      ;;
    --reindex)
      run_reindex=true
      do_all=false
      shift
      ;;
    --workspace-dir)
      if [ $# -lt 2 ]; then
        err "--workspace-dir requires an argument"
        exit 1
      fi
      CLI_WORKSPACE_DIR="$2"
      shift 2
      ;;
    --help | -h)
      show_usage
      exit 0
      ;;
    *)
      err "Неизвестный аргумент: $1"
      exit 1
      ;;
    esac
  done

  resolve_paths
  load_env

  if $do_all; then
    run_backup=true
    run_reindex=true
  fi

  log "=== Day Close (механические шаги) ==="

  local backup_status="skip" git_backup_status="skip" reindex_status="skip"

  if $run_backup; then
    if do_backup; then backup_status="ok"; else backup_status="fail"; fi
    if do_git_backup; then git_backup_status="ok"; else git_backup_status="fail"; fi
  fi

  if $run_reindex; then
    if do_reindex; then reindex_status="ok"; else reindex_status="fail"; fi
  fi

  write_log "$backup_status" "$reindex_status"

  log "=== Готово ==="
  log "  backup=$backup_status  git=$git_backup_status  reindex=$reindex_status"

  if [[ "$backup_status" == "fail" || "$reindex_status" == "fail" ]]; then
    exit 1
  fi
}

main "$@"
