#!/usr/bin/env bash
# eval-week-close.sh — LLM-as-Judge for Week Close E2E
# Usage: bash scripts/test/eval-week-close.sh <workspace_dir> <WeekPlan_path>
# Returns: 0 if ≥5/8 metrics passed, 1 otherwise
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
WEEKPLAN="${2:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }
[ -z "$WEEKPLAN" ] && { echo "ERROR: WeekPlan path required" >&2; exit 1; }
[ ! -f "$WEEKPLAN" ] && { echo "ERROR: WeekPlan not found: $WEEKPLAN" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-week-close.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Week Close ==="
echo "  Plan: $(basename "$WEEKPLAN")"

WEEKPLANS=$(find "$DS_DIR/current" -name "Day*Plan*" 2>/dev/null | head -5 | while read f; do echo "=== $(basename "$f") ==="; head -30 "$f"; done)

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Week Close. Оцени WeekPlan с итогами недели по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Оцениваемый WeekPlan
$(head -250 "$WEEKPLAN" 2>/dev/null)

## Контекст
=== DayPlans за неделю ===
$WEEKPLANS
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== Strategy.md ===
$(cat "$DS_DIR/docs/Strategy.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

AI_CLI_JUDGE="${AI_CLI_JUDGE:-${AI_CLI:-opencode}}"
export AI_CLI="$AI_CLI_JUDGE"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM-as-Judge call failed (rc=$JUDGE_RC)" >&2; exit 2; fi
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2; exit 1
fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
