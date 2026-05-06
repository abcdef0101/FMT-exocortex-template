#!/usr/bin/env bash
# eval-strategy-session.sh — LLM-as-Judge for strategy session WeekPlan
# Usage: bash scripts/test/eval-strategy-session.sh <DS-strategy_dir> <WeekPlan_path>
# Returns: 0 if ≥5/8 metrics passed, 1 otherwise

set -euo pipefail

DS_DIR="${1:-}"
WEEKPLAN="${2:-}"

[ -z "$DS_DIR" ] && { echo "ERROR: DS-strategy directory required" >&2; exit 1; }
[ ! -d "$DS_DIR" ] && { echo "ERROR: directory not found: $DS_DIR" >&2; exit 1; }
[ -z "$WEEKPLAN" ] && { echo "ERROR: WeekPlan path required" >&2; exit 1; }
[ ! -f "$WEEKPLAN" ] && { echo "ERROR: WeekPlan not found: $WEEKPLAN" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-strategy-session.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found: $RUBRICS" >&2; exit 1; }

echo "=== LLM-as-Judge: Strategy Session ==="
echo "  Plan:  $(basename "$WEEKPLAN")"
echo "  DS:    $DS_DIR"

# Find previous WeekPlan for carry-over comparison
PREV_WP=$(find "$DS_DIR/current" -name "WeekPlan*" ! -wholename "$WEEKPLAN" 2>/dev/null | head -1)

# Build judge prompt: rubrics + WeekPlan + seed context files
JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества стратегического плана. Твоя задача: оценить WeekPlan
по 8 критериям. Для каждого критерия прочитай указанные файлы, выставь
score 0.0-1.0 и напиши reasoning (1-2 предложения на русском).

## Критерии
$(cat "$RUBRICS")

## Оцениваемый WeekPlan
$(cat "$WEEKPLAN" | head -200)

## Seed-контекст (файлы для сравнения)

=== Strategy.md ===
$(cat "$DS_DIR/docs/Strategy.md" 2>/dev/null || echo "Strategy.md не найден")

=== Dissatisfactions.md ===
$(cat "$DS_DIR/docs/Dissatisfactions.md" 2>/dev/null || echo "Dissatisfactions.md не найден")

=== Previous WeekPlan ===
$(cat "$PREV_WP" 2>/dev/null | head -120 || echo "Предыдущий WeekPlan не найден")

=== MEMORY.md ===
$(cat "$DS_DIR/memory/MEMORY.md" 2>/dev/null || echo "MEMORY.md не найден")

=== fleeting-notes.md ===
$(cat "$DS_DIR/inbox/fleeting-notes.md" 2>/dev/null || echo "fleeting-notes.md не найден")

## Формат ответа
Верни СТРОГО JSON-массив. Никакого текста до или после JSON.
Пример:
[
  {"metric": "carry_over_fidelity", "score": 0.8, "passed": true, "reasoning": "Все 2 carry-over РП перенесены"},
  ...для всех 8 метрик...
]
PROMPT
)

# Use AI CLI wrapper for judge (separate session from generator)
AI_CLI_JUDGE="${AI_CLI_JUDGE:-${AI_CLI:-opencode}}"
export AI_CLI="$AI_CLI_JUDGE"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

SCRIPT_DIR_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$SCRIPT_DIR_REPO/scripts/ai-cli-wrapper.sh"

if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_OUT=""
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2
  exit 1
fi

# Parse JSON output, compute pass/fail per metric
echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
