#!/bin/bash
# Auditor (Аудитор) Agent Runner
# Запускает Claude Code с заданным сценарием аудита
#
# Использование:
#   auditor.sh --root-dir /path --workspace-dir /path --agent-ai-path /path/to/cli audit-plan-consistency
#   auditor.sh --root-dir /path --workspace-dir /path --agent-ai-path /path/to/cli audit-coverage
#   auditor.sh --root-dir /path --workspace-dir /path --agent-ai-path /path/to/cli on-demand

set -euo pipefail

# === Named parameters ===
ROOT_DIR=""
WORKSPACE_DIR=""
AGENT_AI_PATH=""
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --root-dir)
    ROOT_DIR="$2"
    shift 2
    ;;
  --workspace-dir)
    WORKSPACE_DIR="$2"
    shift 2
    ;;
  --agent-ai-path)
    AGENT_AI_PATH="$2"
    shift 2
    ;;
  *)
    COMMAND="$1"
    shift
    ;;
  esac
done

missing=()
[ -z "$ROOT_DIR" ] && missing+=("--root-dir")
[ -z "$WORKSPACE_DIR" ] && missing+=("--workspace-dir")
[ -z "$AGENT_AI_PATH" ] && missing+=("--agent-ai-path")

if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: required: ${missing[*]}" >&2
  echo "Usage: auditor.sh --root-dir PATH --workspace-dir PATH --agent-ai-path CLI <command>" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR/#\~/$HOME}"
WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"
AGENT_AI_PATH="${AGENT_AI_PATH/#\~/$HOME}"

if [ ! -d "$ROOT_DIR" ]; then
  echo "ERROR: --root-dir does not exist: $ROOT_DIR" >&2
  exit 1
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "ERROR: --workspace-dir does not exist: $WORKSPACE_DIR" >&2
  exit 1
fi

if [ ! -x "$AGENT_AI_PATH" ]; then
  echo "ERROR: --agent-ai-path is not executable: $AGENT_AI_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PROMPTS_DIR="$REPO_DIR/prompts"
LOG_DIR="$WORKSPACE_DIR/logs/auditor"
ENV_FILE="$WORKSPACE_DIR/.env"

# AI CLI: переопределение через переменные окружения (см. extractor.sh)
AI_CLI="${AI_CLI:-$AGENT_AI_PATH}"
AI_CLI_PROMPT_FLAG="${AI_CLI_PROMPT_FLAG:--p}"
AI_CLI_EXTRA_FLAGS="${AI_CLI_EXTRA_FLAGS:---dangerously-skip-permissions --allowedTools Read,Write,Edit,Glob,Grep,Bash}"

mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$DATE.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

notify() {
  local title="$1"
  local message="$2"
  printf 'display notification "%s" with title "%s"' "$message" "$title" | osascript 2>/dev/null ||
    notify-send "$title" "$message" 2>/dev/null ||
    true
}

notify_telegram() {
  local scenario="$1"
  local notify_script="$ROOT_DIR/roles/synchronizer/scripts/notify.sh"
  if [ -f "$notify_script" ]; then
    "$notify_script" --workspace-dir "$WORKSPACE_DIR" --env-file "$ENV_FILE" auditor "$scenario" >>"$LOG_FILE" 2>&1 || true
  fi
}

run_claude() {
  local command_file="$1"
  local extra_args="${2:-}"
  local command_path="$PROMPTS_DIR/$command_file.md"

  if [ ! -f "$command_path" ]; then
    log "ERROR: Command file not found: $command_path"
    exit 1
  fi

  local prompt
  prompt=$(cat "$command_path")

  if [ -n "$extra_args" ]; then
    prompt="$prompt

## Дополнительный контекст

$extra_args"
  fi

  # Inject date context (prevents LLM calendar arithmetic errors)
  local ru_date_context
  ru_date_context=$(python3 -c "
import datetime
days = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье']
months = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря']
d = datetime.date.today()
print(f'{d.day} {months[d.month-1]} {d.year}, {days[d.weekday()]}')
")
  prompt="[Системный контекст] Сегодня: ${ru_date_context}. ISO: ${DATE}. ЯЗЫК: отвечай ТОЛЬКО на русском.

${prompt}"

  log "Starting scenario: $command_file"
  log "Command file: $command_path"

  cd "$WORKSPACE_DIR"

  local rc=0
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"

  if [ -f "$WRAPPER" ]; then
    source "$WRAPPER"
    AI_CLI_TIMEOUT="${AI_CLI_TIMEOUT:-1800}"
    ai_cli_run "$prompt" --bare --allowed-tools "Read,Write,Edit,Glob,Grep,Bash" \
      >>"$LOG_FILE" 2>&1 || rc=$?
  else
    "$AI_CLI" $AI_CLI_EXTRA_FLAGS \
      $AI_CLI_PROMPT_FLAG "$prompt" \
      >>"$LOG_FILE" 2>&1 || rc=$?
  fi

  if [ $rc -eq 124 ]; then
    log "WARN: AI CLI timed out after ${AI_CLI_TIMEOUT:-1800}s for scenario: $command_file"
  fi

  log "Completed scenario: $command_file"
  notify "Аудитор: $command_file" "Аудит завершён"
}

case "$COMMAND" in
"audit-plan-consistency")
  log "Running plan consistency audit"
  run_claude "audit-plan-consistency"
  notify_telegram "audit-plan-consistency"
  ;;

"audit-coverage")
  log "Running coverage audit"
  run_claude "audit-coverage"
  notify_telegram "audit-coverage"
  ;;

"on-demand")
  log "Running on-demand audit"
  run_claude "audit-plan-consistency"
  notify_telegram "on-demand"
  ;;

*)
  echo "Auditor (Аудитор, R24)"
  echo ""
  echo "Usage: $0 --root-dir PATH --workspace-dir PATH --agent-ai-path CLI <command>"
  echo ""
  echo "Required:"
  echo "  --root-dir PATH          Base directory of IWE template (must exist)"
  echo "  --workspace-dir PATH     Workspace directory (must exist)"
  echo "  --agent-ai-path CLI      Path to AI agent executable (e.g. claude)"
  echo ""
  echo "Commands:"
  echo "  audit-plan-consistency  Кросс-контекстная проверка планов (VR.M.002)"
  echo "  audit-coverage          Аудит покрытия: source → target (VR.M.004)"
  echo "  on-demand               Аудит по запросу (псевдоним audit-plan-consistency)"
  exit 1
  ;;
esac

log "Done"
