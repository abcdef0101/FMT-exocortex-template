#!/usr/bin/env bash
# day-close.sh — Единый entry-point для механических шагов Day Close.
#
# Вызывается из .claude/skills/day-close/SKILL.md.
# НЕ содержит бизнес-логику Day Close — только механические операции.
#
# Использование:
#   day-close.sh --collect-data    # шаг 1: сбор коммитов за сегодня
#   day-close.sh --drift-scan      # шаг 4: поиск устаревших фактов в MEMORY.md
#   day-close.sh --index-health    # шаг 5: проверка раздутия индекс-файлов
#   day-close.sh --backup-memory   # шаг 7: backup memory/ в workspace repo
#   day-close.sh                   # то же что --backup-memory (совместимость)
#
# Вызов из SKILL.md: bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" --<subcommand>
#
# Конфигурация через env vars:
#   IWE_DAY_CLOSE_LOG — путь к log-файлу
#   MEMORY_BACKUP     — коммитить memory в workspace git repo (default: true)
#
# Exit codes: 0=success, 1=error/bad-arg

set -euo pipefail

# globals (set by resolve_paths / resolve_config, read by do_*)
FMT_DIR=""
WORKSPACE_MEMORY=""
WORKSPACE_DIR=""
CLI_WORKSPACE_DIR=""
MEMORY_BACKUP=""
LOG_FILE=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[day-close]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[day-close]${NC} $1" >&2; }
err() { echo -e "${RED}[day-close]${NC} $1" >&2; }

show_usage() {
  echo "Использование: day-close.sh [--workspace-dir DIR] <subcommand>"
  echo "  --workspace-dir DIR — использовать указанный workspace"
  echo ""
  echo "Subcommands:"
  echo "  --collect-data     Собрать коммиты за сегодня по всем репо в workspace"
  echo "  --drift-scan       Найти устаревшие блокеры/зависимости в MEMORY.md"
  echo "  --index-health     Проверить раздутие индекс-файлов (check-index-health.py)"
  echo "  --backup-memory    Закоммитить memory/ и CLAUDE.md (default)"
}

load_env() {
  local env_file="$WORKSPACE_DIR/.env"
  if [ -f "$env_file" ]; then
    while IFS='=' read -r key value; do
      value="${value#\"}"
      value="${value%\"}"
      case "$key" in
      MEMORY_BACKUP) MEMORY_BACKUP="$value" ;;
      esac
    done <"$env_file"
  fi
  MEMORY_BACKUP="${MEMORY_BACKUP:-true}"
}

_resolve_lib="$(cd "$(dirname "$0")/../../../scripts" && pwd)/resolve-workspace.sh"
if [ ! -f "$_resolve_lib" ]; then
  echo "ERROR: resolve-workspace.sh not found: $_resolve_lib" >&2
  exit 1
fi
# shellcheck source=resolve-workspace.sh
source "$_resolve_lib"
unset _resolve_lib

resolve_config() {
  LOG_FILE="${IWE_DAY_CLOSE_LOG:-$WORKSPACE_DIR/DS-agent-workspace/scheduler/day-close.log}"
}

resolve_paths() {
  resolve_fmt_dir
  resolve_workspace
  resolve_config
}

do_collect_data() {
  local today
  today=$(date +%Y-%m-%d)
  local found=0
  for repo in "$WORKSPACE_DIR"/*/; do
    [ -d "$repo/.git" ] || continue
    local name
    name=$(basename "$repo")
    local commits
    commits=$(git -C "$repo" log --since="$today 00:00" --until="$today 23:59:59" --oneline --no-merges 2>/dev/null)
    if [ -n "$commits" ]; then
      echo "=== $name ==="
      echo "$commits"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "(нет коммитов за сегодня)"
  fi
}

do_drift_scan() {
  if [ ! -f "$WORKSPACE_DIR/memory/MEMORY.md" ]; then
    echo "MEMORY.md не найден — drift-scan пропущен"
    return 0
  fi
  grep -nE "→ ждёт|ждёт|dep:|блокер|blocked:|остановлен|ждёт согласования" \
    "$WORKSPACE_DIR/memory/MEMORY.md" 2>/dev/null || echo "(drift-паттернов не найдено)"
}

do_index_health() {
  local script="$WORKSPACE_DIR/DS-strategy/scripts/check-index-health.py"
  if [ -f "$script" ]; then
    python3 "$script"
  else
    echo "check-index-health.py не установлен — шаг пропущен"
  fi
}

do_backup_memory() {
  log "Backup memory/ → workspace repo"
  if [ "$MEMORY_BACKUP" != "true" ]; then
    log "  MEMORY_BACKUP=$MEMORY_BACKUP — backup memory пропущен"
    return 0
  fi

  local ws_git="$WORKSPACE_DIR"
  if [ ! -d "$ws_git/.git" ]; then
    warn "  workspace не является git-репозиторием: $ws_git — backup memory пропущен"
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

  if [ "${#files_to_commit[@]}" -eq 0 ]; then
    log "  Нет файлов для backup memory"
    return 0
  fi

  git -C "$ws_git" add "${files_to_commit[@]+"${files_to_commit[@]}"}" 2>&1 || {
    warn "  git add failed"
    return 1
  }

  if git -C "$ws_git" diff --cached --quiet 2>/dev/null; then
    log "  Backup memory: нет изменений для коммита"
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
    log "  Backup memory: commit + push выполнен (${#files_to_commit[@]} файлов)"
  else
    log "  Backup memory: commit выполнен (no remote, push skipped)"
  fi
}


write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | day-close | backup=$1" >>"$LOG_FILE"
}

main() {
  CLI_WORKSPACE_DIR=""
  local subcommand="--backup-memory"

  while [ $# -gt 0 ]; do
    case "$1" in
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
    --collect-data | --drift-scan | --index-health | --backup-memory)
      subcommand="$1"
      shift
      ;;
    *)
      err "Неизвестный аргумент: $1"
      exit 1
      ;;
    esac
  done

  resolve_paths
  load_env

  case "$subcommand" in
  --collect-data)  do_collect_data ;;
  --drift-scan)    do_drift_scan ;;
  --index-health)  do_index_health ;;
  --backup-memory)
    log "=== Day Close: backup memory ==="
    local backup_memory_status="skip"
    if do_backup_memory; then backup_memory_status="ok"; else backup_memory_status="fail"; fi
    write_log "$backup_memory_status"
    log "=== Готово ==="
    log "  backup-memory=$backup_memory_status"
    if [[ "$backup_memory_status" == "fail" ]]; then
      exit 1
    fi
    ;;
  esac
}

main "$@"
