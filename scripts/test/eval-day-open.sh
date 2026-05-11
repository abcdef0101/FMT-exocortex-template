#!/usr/bin/env bash
# eval-day-open.sh — LLM-as-Judge for Day Open E2E DayPlan
# Usage: bash scripts/test/eval-day-open.sh <workspace_dir> <DayPlan_path> [--run]
#   --run: first execute Day Open via AI CLI, then judge the result
# Returns: 0 if ≥6/8 metrics passed, 1 otherwise, 2 if AI call failed
set -euo pipefail

# Load AI secrets from file
if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

WS_DIR="${1:-}"
DAYPLAN="${2:-}"

# === Run Day Open process ===
if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
  [ ! -f "$WRAPPER" ] && { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"
  DS_DIR="$WS_DIR/DS-strategy"
  [ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

  DAYOPEN_PROMPT="Execute Day Open in workspace $WS_DIR.
Read WeekPlan, MEMORY.md, last 2 days DayPlans, fleeting-notes.
Build today's DayPlan with: план на сегодня (table), календарь, carry-over,
саморазвитие (slot 1), «Требует внимания», compact dashboard.
This is an automated test — auto-approve, skip verification."

  echo "=== Day Open: running AI process ==="
  AI_CLI_TIMEOUT=600
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RUN_OUT=$(ai_cli_run "$DAYOPEN_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null) || RUN_RC=$?
  if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Day Open AI failed" >&2; exit 2; fi
  echo "=== Day Open: AI process done ==="
fi

[ -z "$WS_DIR" ] && { echo "ERROR: workspace directory required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: directory not found: $WS_DIR" >&2; exit 1; }
[ "$DAYPLAN" = "--run" ] && DAYPLAN=""
[ -z "$DAYPLAN" ] && DAYPLAN=$(find "$WS_DIR" -name 'DayPlan*' -type f 2>/dev/null | sort | tail -1)
[ -z "$DAYPLAN" ] && { echo "ERROR: DayPlan path required" >&2; exit 1; }
[ ! -f "$DAYPLAN" ] && { echo "ERROR: DayPlan not found: $DAYPLAN" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-day-open.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found: $RUBRICS" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Day Open ==="
echo "  Plan:      $(basename "$DAYPLAN")"
echo "  Workspace: $WS_DIR"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "$TODAY -1 day" +%Y-%m-%d 2>/dev/null || date -d "$TODAY -1 day" +%Y-%m-%d)

# Build judge prompt: rubrics + DayPlan + seed context files
JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества дневного плана (DayPlan). Твоя задача: оценить DayPlan
по 8 критериям. Для каждого критерия прочитай указанные файлы, выставь
score 0.0-1.0 и напиши reasoning (1-2 предложения на русском).

## Критерии
$(cat "$RUBRICS")

## Оцениваемый DayPlan
$(cat "$DAYPLAN" | head -200)

## Seed-контекст (файлы для сравнения)

=== WeekPlan (текущая неделя) ===
$(cat "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null | head -150 || echo "WeekPlan не найден")

=== DayPlan (вчера, с итогами) ===
$(find "$DS_DIR/current" -name "Day*Plan*${YESTERDAY}"*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -100 || echo "Вчерашний DayPlan не найден")

=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "MEMORY.md не найден")

=== fleeting-notes.md ===
$(cat "$DS_DIR/inbox/fleeting-notes.md" 2>/dev/null || echo "fleeting-notes.md не найден")

=== seed-issues.md ===
$(cat "$DS_DIR/inbox/seed-issues.md" 2>/dev/null || echo "seed-issues.md не найден")

## Формат ответа
Верни СТРОГО JSON-массив. Никакого текста до или после JSON.
Пример:
[
  {"metric": "carry_over_fidelity", "score": 0.8, "passed": true, "reasoning": "..."},
  ...для всех 8 метрик...
]
PROMPT
)

# Use AI CLI wrapper for judge (separate session from generator)
AI_CLI_JUDGE="${AI_CLI_JUDGE:-opencode}"
export AI_CLI="$AI_CLI_JUDGE"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

SCRIPT_DIR_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$SCRIPT_DIR_REPO/scripts/ai-cli-wrapper.sh"

if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then
    echo "LLM_JUDGE_PASS=0"
    echo "LLM_JUDGE_TOTAL=0"
    echo "ERROR: LLM-as-Judge call failed (rc=$JUDGE_RC)" >&2
    exit 2
  fi
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2
  exit 1
fi

# Parse JSON output, compute pass/fail per metric
echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 6 2>&1
