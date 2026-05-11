#!/usr/bin/env bash
# eval-skill-invocation-e2e.sh — /verify pack-entity skill invocation E2E
# Usage: bash scripts/test/eval-skill-invocation-e2e.sh <workspace_dir> [--run]
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
REPORT_FILE="$WS_DIR/verification-skill-report.md"

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  VERIFY_PROMPT="Execute /verify pack-entity on $WS_DIR/Pack/08-service-clauses/DP.SC.025-capture-bus.md.
Read the DP standard from $WS_DIR/DS-strategy/docs/DP-standard.md.
Detect violations: missing sections, insufficient acceptance criteria, formatting issues.
Write the result to $REPORT_FILE.
Output: structured findings with severity (P0/P1/P2), evidence, description."

  echo "=== Skill Invocation: /verify pack-entity ==="
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$VERIFY_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null || { echo "ERROR: Skill invocation failed" >&2; exit 2; }
  [ -f "$REPORT_FILE" ] || { echo "ERROR: skill report not created" >&2; exit 3; }
  echo "=== Skill Invocation: done ==="
fi

echo "=== Structural Check: Skill Invocation ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/assert-skill-invocation.sh" "$WS_DIR" 2>&1
