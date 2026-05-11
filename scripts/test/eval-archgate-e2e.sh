#!/usr/bin/env bash
# eval-archgate-e2e.sh — ArchGate E2E: AI evaluates architectural decision
# Usage: bash scripts/test/eval-archgate-e2e.sh <workspace_dir> [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
REPORT_FILE="$WS_DIR/docs/adr/archgate-report.md"

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  ARCHGATE_PROMPT="Evaluate the architectural decision in $WS_DIR/docs/adr/sample-decision.md.
Read CLAUDE.md for ArchGate rules. Read .claude/skills/archgate/SKILL.md for the full protocol.
Produce a 7-row ЭМОГССБ table with ✅⚠️❌ for each characteristic.
Apply 3 veto rules. Check 3 modernity items.
Write the result to $REPORT_FILE.
Output: gate decision (pass/fail) with reasoning."

  echo "=== ArchGate: running AI process ==="
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$ARCHGATE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null || { echo "ERROR: ArchGate AI failed" >&2; exit 2; }
  [ -f "$REPORT_FILE" ] || { echo "ERROR: ArchGate report not created" >&2; exit 3; }
  echo "=== ArchGate: AI process done ==="
fi

echo "=== LLM-as-Judge: ArchGate ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-archgate.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества ArchGate. Оцени правильность применения 7 характеристик к решению по 8 критериям.
score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Решение для оценки
$(cat "$WS_DIR/docs/adr/sample-decision.md" 2>/dev/null || echo "N/A")

## Отчёт ArchGate
$(cat "$REPORT_FILE" 2>/dev/null || echo "N/A")

## Правила ArchGate (из CLAUDE.md)
$(cat "$WS_DIR/CLAUDE.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=90

WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || { echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; exit 2; }
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
