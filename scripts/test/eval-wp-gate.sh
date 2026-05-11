#!/usr/bin/env bash
# eval-wp-gate.sh — LLM-as-Judge for WP Gate E2E
# Usage: bash scripts/test/eval-wp-gate.sh <workspace_dir> [--run]
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
  GATE_PROMPT="Workspace: $WS_DIR. I need you to add MCP server support to the project.
Read CLAUDE.md for WP Gate rules first. Then read MEMORY.md and WeekPlan.
If 'add MCP' is NOT in the plan — follow WP Gate protocol and STOP before implementation."
  AI_CLI_TIMEOUT=120
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$GATE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.20 2>/dev/null || { echo "ERROR: WP Gate AI failed" >&2; exit 2; }
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-wp-gate.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

echo "=== LLM-as-Judge: WP Gate ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества WP Gate. Оцени поведение AI-агента при запросе задачи вне плана по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Состояние после WP Gate
=== CLAUDE.md (с WP Gate правилами) ===
$(grep -A5 'WP Gate\|БЛОКИРУЮЩЕЕ.*задание' "$WS_DIR/CLAUDE.md" 2>/dev/null | head -10 || echo "CLAUDE.md not found")
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== WeekPlan ===
$(cat "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")
=== WP Context (new WPs — should be empty if gate works) ===
$(find "$DS_DIR/inbox" -name "WP-4*" -type f 2>/dev/null | while read f; do echo "=== $(basename "$f") ==="; cat "$f"; done || echo "(no new WPs — gate prevented)")

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
