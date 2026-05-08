#!/usr/bin/env bash
# eval-wp-new.sh — LLM-as-Judge for wp-new E2E
# Usage: bash scripts/test/eval-wp-new.sh <workspace_dir> [--run]
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
RUBRICS="$SCRIPT_DIR/rubrics-wp-new.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
DS_DIR="$WS_DIR/DS-strategy"

if $RUN_MODE; then
  [ ! -f "$WRAPPER" ] && { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  # Concise wp-new prompt
  WPNEW_PROMPT="Create a new work product 'WP-5 CI gates' (budget 4h) in workspace $WS_DIR.
Atomic write to 5 locations:
1. WP-REGISTRY: $DS_DIR/docs/WP-REGISTRY.md — add row | 5 | WP-5 CI gates | pending |
2. MEMORY.md: $WS_DIR/memory/MEMORY.md — add WP-5 to table
3. WeekPlan: $(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1) — add row with budget 4h
4. DayPlan: $(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1) — add to plan
5. WP Context: create $DS_DIR/inbox/WP-5-ci-gates.md with '## Осталось' section
Use noun-artifact naming. Next sequential integer number."

  echo "=== wp-new: running AI process ==="
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RUN_OUT=$(ai_cli_run "$WPNEW_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.25 2>/dev/null) || RUN_RC=$?
  if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: wp-new AI failed" >&2; exit 2; fi
  echo "=== wp-new: AI process done ==="
fi

echo "=== LLM-as-Judge: wp-new ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества wp-new. Проверь что новый РП WP-5 записан во все 5 мест атомарно.
Оцени по 8 критериям. Для каждого: score 0.0-1.0, passed, reasoning (русский).

## Критерии
$(cat "$RUBRICS")

## Состояние ПОСЛЕ wp-new
=== WP-REGISTRY ===
$(cat "$DS_DIR/docs/WP-REGISTRY.md" 2>/dev/null || echo "N/A")
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== WeekPlan ===
$(head -60 "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")
=== DayPlan ===
$(head -40 "$DS_DIR/current/DayPlan"*".md" 2>/dev/null || echo "N/A")
=== WP Context (новый) ===
$(find "$DS_DIR/inbox" -name "WP-5*" 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "N/A")

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
