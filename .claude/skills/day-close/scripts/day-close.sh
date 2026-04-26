#!/bin/bash
# day-close.sh — Механические шаги Day Close (backup + reindex + linear sync)
#
# Вызывается из .claude/skills/day-close/SKILL.md (шаг 4).
# НЕ содержит бизнес-логику Day Close — только механические операции.
#
# Backup: копирует workspace memory/ (MEMORY.md, day-rhythm-config.yaml, etc.)
# в DS-strategy/exocortex/. Symlinks (persistent-memory) пропускаются.
#
# Использование:
#   day-close.sh              # все три шага
#   day-close.sh --backup     # только backup
#   day-close.sh --reindex    # только reindex
#   day-close.sh --linear     # только linear sync
#
# Конфигурация: WORKSPACE_DIR через env var или --workspace-dir.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[day-close]${NC} $1"; }
warn() { echo -e "${YELLOW}[day-close]${NC} $1"; }
err() { echo -e "${RED}[day-close]${NC} $1" >&2; }

show_usage() {
  echo "Использование: day-close.sh [--backup] [--reindex] [--linear] [--workspace-dir DIR]"
  echo "  Без аргументов — все три шага"
}

resolve_paths() {
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  FMT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

  WORKSPACE_LINK="$FMT_DIR/workspaces/CURRENT_WORKSPACE"
  WORKSPACE_MEMORY=""
  if [ -L "$WORKSPACE_LINK" ]; then
    local ws_target
    ws_target="$(readlink "$WORKSPACE_LINK")"
    local ws_dir=""
    if [ -d "$FMT_DIR/workspaces/$ws_target" ]; then
      ws_dir="$FMT_DIR/workspaces/$ws_target"
    elif [ -d "$ws_target" ]; then
      ws_dir="$ws_target"
    fi
    if [ -n "$ws_dir" ] && [ -d "$ws_dir/memory" ]; then
      WORKSPACE_MEMORY="$ws_dir/memory"
    fi
  fi
  EXOCORTEX_DST="$DS_STRATEGY/exocortex"
  SELECTIVE_REINDEX="$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/selective-reindex.sh"
  SOURCES_JSON="$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/sources.json"
  SOURCES_PERSONAL_JSON="$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/sources-personal.json"
  PARAMS_YAML="$WORKSPACE_DIR/params.yaml"

  LINEAR_SYNC=""
  if [ -f "$PARAMS_YAML" ]; then
    local raw
    raw=$(python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d.get('linear_sync_path',''))" "$PARAMS_YAML" 2>/dev/null || echo "")
    if [ -n "$raw" ]; then
      LINEAR_SYNC="${raw/#\~/$HOME}"
    fi
  fi
  LOG_FILE="$WORKSPACE_DIR/DS-agent-workspace/scheduler/day-close.log"
}

do_backup() {
  log "Шаг 1/3: Backup workspace memory/ → exocortex/"

  mkdir -p "$EXOCORTEX_DST"

  local count=0

  if [ -d "$WORKSPACE_MEMORY" ]; then
    for f in "$WORKSPACE_MEMORY"/*; do
      [ -f "$f" ] || continue
      local bname
      bname=$(basename "$f")
      case "$bname" in
        *.md|*.yaml|*.yml|*.json) ;;
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

do_reindex() {
  log "Шаг 2/3: Knowledge-MCP reindex"

  if [ ! -x "$SELECTIVE_REINDEX" ]; then
    warn "  selective-reindex.sh не найден: $SELECTIVE_REINDEX — пропуск"
    return 0
  fi

  local dir_map
  dir_map=$(python3 - "$SOURCES_JSON" "$SOURCES_PERSONAL_JSON" << 'PYEOF'
import sys, json, os
for config_path in sys.argv[1:]:
    if not os.path.exists(config_path):
        continue
    for s in json.load(open(config_path)):
        resolved = os.path.expanduser(s["path"])
        while not os.path.isdir(os.path.join(resolved, ".git")) and resolved != "/":
            resolved = os.path.dirname(resolved)
        if resolved == "/":
            continue
        print(f"{os.path.basename(resolved)}\t{s['source']}\t{config_path}")
PYEOF
  ) || { warn "  Mapping build failed — пропуск reindex"; return 0; }

  local l2_sources="" l4_sources=""
  for repo in "$WORKSPACE_DIR"/PACK-* "$WORKSPACE_DIR"/DS-*; do
    [ -d "$repo/.git" ] || continue
    local repo_name
    repo_name=$(basename "$repo")
    local today_commits
    today_commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')
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

do_linear() {
  log "Шаг 3/3: Linear sync"

  if [ ! -x "$LINEAR_SYNC" ]; then
    warn "  linear-sync.sh не найден — пропуск"
    return 0
  fi

  "$LINEAR_SYNC"
}

write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | day-close | backup=$1 reindex=$2 linear=$3" >> "$LOG_FILE"
}

main() {
  local do_all=true
  local run_backup=false
  local run_reindex=false
  local run_linear=false

  WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --backup)  run_backup=true; do_all=false; shift ;;
      --reindex) run_reindex=true; do_all=false; shift ;;
      --linear)  run_linear=true; do_all=false; shift ;;
      --workspace-dir)
        if [ $# -lt 2 ]; then err "--workspace-dir требует аргумент"; exit 1; fi
        WORKSPACE_DIR="$2"; shift 2 ;;
      --help|-h)
        show_usage; exit 0 ;;
      *)
        err "Неизвестный аргумент: $1"; exit 1 ;;
    esac
  done

  resolve_paths

  if $do_all; then
    run_backup=true
    run_reindex=true
    run_linear=true
  fi

  log "=== Day Close (механические шаги) ==="

  local backup_status="skip" reindex_status="skip" linear_status="skip"

  if $run_backup; then
    if do_backup; then backup_status="ok"; else backup_status="fail"; fi
  fi

  if $run_reindex; then
    if do_reindex; then reindex_status="ok"; else reindex_status="fail"; fi
  fi

  if $run_linear; then
    if do_linear; then linear_status="ok"; else linear_status="fail"; fi
  fi

  write_log "$backup_status" "$reindex_status" "$linear_status"

  log "=== Готово ==="
  log "  backup=$backup_status  reindex=$reindex_status  linear=$linear_status"

  if [[ "$backup_status" == "fail" || "$reindex_status" == "fail" || "$linear_status" == "fail" ]]; then
    exit 1
  fi
}

main "$@"
