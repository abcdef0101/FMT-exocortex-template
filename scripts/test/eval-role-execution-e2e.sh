#!/usr/bin/env bash
# eval-role-execution-e2e.sh — Strategist morning role execution E2E
# Usage: bash scripts/test/eval-role-execution-e2e.sh <workspace_dir> [--run]
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

  ROLE_PROMPT="Execute the strategist morning scenario in workspace $WS_DIR.
Read WeekPlan, MEMORY.md, previous DayPlan, CLAUDE.md.
Build today's DayPlan: план на сегодня (table), carry-over from yesterday,
календарь, self-development slot, compact dashboard.
This is automated test — auto-approve, skip verification."

  echo "=== Role Execution: strategist morning ==="
  AI_CLI_TIMEOUT=600
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$ROLE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null || { echo "ERROR: Role execution failed" >&2; exit 2; }
  echo "=== Role Execution: done ==="
fi

echo "=== Structural Check: Role Execution ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/assert-role-execution.sh" "$WS_DIR" 2>&1
