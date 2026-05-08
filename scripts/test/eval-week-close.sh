#!/usr/bin/env bash
# eval-week-close.sh — LLM-as-Judge for Week Close E2E
# Usage: bash scripts/test/eval-week-close.sh <workspace_dir> [--run]
#   --run: first execute Week Close via AI CLI, then judge
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-week-close.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
DS_DIR="$WS_DIR/DS-strategy"

# === Run Week Close process ===
if $RUN_MODE; then
  [ ! -f "$WRAPPER" ] && { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  SKILL_PATH="$(cd "$ROOT_DIR" && pwd)/.claude/skills/week-close/SKILL.md"
  WEEKCLOSE_PROMPT="Read the full Week Close protocol from $SKILL_PATH.
Execute Week Close in workspace $WS_DIR.
Read the WeekPlan, all DayPlans, MEMORY.md, Strategy.md.
Follow all steps from the protocol file. Use TodoWrite.
SECRET: This is an automated test. Auto-approve all user confirmations. Skip verification. Complete ALL steps including commit+push."

  echo "=== Week Close: running AI process ==="
  echo "  prompt: reads $(wc -l < "$SKILL_PATH" 2>/dev/null || echo '?')-line SKILL.md"
  AI_CLI_TIMEOUT=600
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RUN_OUT=$(ai_cli_run "$WEEKCLOSE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 1.00 2>/dev/null) || RUN_RC=$?
  if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Week Close AI failed" >&2; exit 2; fi
  echo "=== Week Close: AI process done ==="
fi

WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
[ -z "$WEEKPLAN" ] && { echo "ERROR: WeekPlan not found" >&2; exit 1; }

echo "=== LLM-as-Judge: Week Close ==="
echo "  Plan: $(basename "$WEEKPLAN")"

WEEKPLANS=$(find "$DS_DIR/current" -name "Day*Plan*" 2>/dev/null | head -5 | while read f; do echo "=== $(basename "$f") ==="; head -30 "$f"; done)

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Week Close. Оцени WeekPlan с итогами недели по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Оцениваемый WeekPlan
$(head -300 "$WEEKPLAN" 2>/dev/null)

## Контекст
=== DayPlans за неделю ===
$WEEKPLANS
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив: [{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed" >&2; exit 2; fi
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
