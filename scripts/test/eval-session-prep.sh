#!/usr/bin/env bash
# eval-session-prep.sh — LLM-as-Judge for Session Prep (headless) E2E
# Returns: 0 if ≥5/8 metrics passed, 1 otherwise
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-session-prep.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Session Prep ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Session Prep (headless). Оцени создание черновика
WeekPlan по 8 критериям. Для каждого: score 0.0-1.0, passed, reasoning (русский).

## Критерии
$(cat "$RUBRICS")

## Входные данные (seed)
=== Previous WeekPlan (W13) ===
$(cat "$DS_DIR/current/WeekPlan W13"*".md" 2>/dev/null | head -100 || echo "N/A")
=== Previous DayPlan ===
$(cat "$DS_DIR/current/DayPlan"*".md" 2>/dev/null | head -60 || echo "N/A")
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== Strategy.md ===
$(cat "$DS_DIR/docs/Strategy.md" 2>/dev/null || echo "N/A")
=== Dissatisfactions.md ===
$(cat "$DS_DIR/docs/Dissatisfactions.md" 2>/dev/null || echo "N/A")
=== fleeting-notes.md ===
$(cat "$DS_DIR/inbox/fleeting-notes.md" 2>/dev/null || echo "N/A")
=== Session Agenda ===
$(cat "$DS_DIR/docs/Session Agenda.md" 2>/dev/null || echo "N/A")

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
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed (rc=$JUDGE_RC)" >&2; exit 2; fi
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2; exit 1
fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
