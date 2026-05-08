#!/usr/bin/env bash
# eval-orz-cycle.sh — LLM-as-Judge for ORZ Full Cycle E2E
# Usage: bash scripts/test/eval-orz-cycle.sh <workspace_dir> [--run]
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

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"
  ORZ_PROMPT="Execute full ORZ cycle for WP-1 in workspace $WS_DIR.
Open: check WP Gate — WP-1 is in MEMORY.md and WeekPlan → proceed.
Work: read DayPlan, WeekPlan, MEMORY, WP Context. Do the work described.
Close (Quick Close): commit+push, update WP Context Осталось, KE routing, update MEMORY status.
This is automated test — auto-approve all confirmations, skip verification."
  AI_CLI_TIMEOUT=600
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$ORZ_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null || { echo "ERROR: ORZ Cycle AI failed" >&2; exit 2; }
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-orz-cycle.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

echo "=== LLM-as-Judge: ORZ Full Cycle ==="

WP_CONTEXT=$(find "$DS_DIR/inbox" -name "WP-1*" -type f 2>/dev/null | head -1)
SESSION_LOG="$DS_DIR/inbox/open-sessions.log"

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества полного цикла ОРЗ (Open → Work → Close). Оцени по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Состояние после цикла
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== WeekPlan ===
$(cat "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")
=== WP Context ===
$(cat "$WP_CONTEXT" 2>/dev/null || echo "N/A")
=== Session Log ===
$(cat "$SESSION_LOG" 2>/dev/null || echo "N/A")
=== CLAUDE.md (captures) ===
$(head -30 "$WS_DIR/CLAUDE.md" 2>/dev/null || echo "N/A")

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
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed" >&2; exit 2; fi
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
