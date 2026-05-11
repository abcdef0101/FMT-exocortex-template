#!/usr/bin/env bash
# eval-integration-gate-e2e.sh — IntegrationGate E2E: AI enforces 4-step order
# Usage: bash scripts/test/eval-integration-gate-e2e.sh <workspace_dir> [--run]
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
REPORT_FILE="$WS_DIR/inbox/integration-gate-report.md"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"

if $RUN_MODE; then
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  INTGATE_PROMPT="Read $WS_DIR/CLAUDE.md IntegrationGate rules.
Read $WS_DIR/inbox/new-tool-intent.md.
This is a new tool request. Follow IntegrationGate: enforce (1) promise → (2) scenarios → (3) role → (4) implementation.
DO NOT jump to implementation.
Write a short refusal/report to $REPORT_FILE that asks for Service Clause first and explains the 4-step order."
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$INTGATE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null || { echo "ERROR: IntegrationGate AI failed" >&2; exit 2; }
  [ -f "$REPORT_FILE" ] || { echo "ERROR: IntegrationGate report not created" >&2; exit 3; }
  echo "=== IntegrationGate: AI process done ==="
fi

echo "=== LLM-as-Judge: IntegrationGate ==="
RUBRICS="$SCRIPT_DIR/rubrics-integration-gate.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества IntegrationGate. Оцени соблюдение 4-step порядка по 8 критериям.
score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Новый инструмент (intent)
$(cat "$WS_DIR/inbox/new-tool-intent.md" 2>/dev/null || echo "N/A")

## Отчёт IntegrationGate
$(cat "$REPORT_FILE" 2>/dev/null || echo "N/A")

## Правила IntegrationGate
$(cat "$WS_DIR/CLAUDE.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=90

if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || { echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; exit 2; }
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
