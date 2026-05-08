#!/usr/bin/env bash
# eval-day-close.sh — LLM-as-Judge for Day Close E2E
# Usage: bash scripts/test/eval-day-close.sh <workspace_dir> <DayPlan_path>
# Returns: 0 if ≥6/8 metrics passed, 1 otherwise
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
DAYPLAN="${2:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }
[ -z "$DAYPLAN" ] && { echo "ERROR: DayPlan path required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-day-close.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Day Close ==="
echo "  Plan: $(basename "$DAYPLAN")"

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Day Close. Оцени DayPlan с итогами дня по 8 критериям.
Для каждого критерия: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Оцениваемый DayPlan (с итогами)
$(head -200 "$DAYPLAN" 2>/dev/null || echo "DayPlan not found")

## Контекст
=== WeekPlan ===
$(head -80 "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== WP-REGISTRY ===
$(cat "$DS_DIR/docs/WP-REGISTRY.md" 2>/dev/null || echo "N/A")
=== Previous DayPlan ===
$(find "$DS_DIR/current" -name "Day*Plan*" ! -path "$DAYPLAN" 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -60 || echo "N/A")

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
  if [ "$JUDGE_RC" -ne 0 ]; then
    echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"
    echo "ERROR: LLM-as-Judge call failed (rc=$JUDGE_RC)" >&2
    exit 2
  fi
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2; exit 1
fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
