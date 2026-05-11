#!/usr/bin/env bash
# eval-verifier-pack-entity.sh — LLM-as-Judge for Verifier pack-entity E2E
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
REPORT_FILE="$WS_DIR/verification-pack-entity.md"

if $RUN_MODE; then
  WRAPPER="$(cd "$(dirname "$0")/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$WRAPPER"

  VERIFY_PROMPT="Verify $WS_DIR/Pack/08-service-clauses/DP.SC.025-capture-bus.md against $WS_DIR/DS-strategy/docs/DP-standard.md.
Write the result to $REPORT_FILE.
The report must include PASS/FAIL/CONDITIONAL, evidence with path:line, and explicit findings for:
- missing Dependencies section
- insufficient acceptance criteria count
- missing Created/temporal metadata if absent"

  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  AI_CLI_TIMEOUT=300
  ai_cli_run "$VERIFY_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.30 2>/dev/null || { echo "ERROR: Verifier AI failed" >&2; exit 2; }
  [ -f "$REPORT_FILE" ] || { echo "ERROR: verifier report not created" >&2; exit 3; }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-verifier-pack-entity.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

echo "=== LLM-as-Judge: Verifier Pack Entity ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Verifier pack-entity. Оцени обнаружение нарушений в Pack-файле по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Отчёт верификации
$(cat "$REPORT_FILE" 2>/dev/null || echo "N/A")

## Файл для проверки (Pack/08-service-clauses/DP.SC.025-capture-bus.md)
$(cat "$WS_DIR/Pack/08-service-clauses/DP.SC.025-capture-bus.md" 2>/dev/null || echo "N/A")

## Эталон (стандарт Service Clause)
$(cat "$WS_DIR/DS-strategy/docs/DP-standard.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.15 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed" >&2; exit 2; fi
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
