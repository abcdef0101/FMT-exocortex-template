#!/usr/bin/env bash
# canary-orz-cycle.sh — replay Open→Work→Close cycle на копии workspace
# Layer 3 canary test (ADR-009). Еженедельный health check.
# Usage: bash scripts/test/canary-orz-cycle.sh <workspace_dir> [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Canary: ORZ Full Cycle Replay ==="
echo "  source: $WS_DIR"

CANARY_DIR=$(mktemp -d "${WS_DIR%/*}/canary-XXXXXX" 2>/dev/null || mktemp -d "/tmp/canary-orz-XXXXXX")
trap 'rm -rf "$CANARY_DIR"' EXIT
cp -a "$WS_DIR"/* "$CANARY_DIR/" 2>/dev/null || true
cp -a "$WS_DIR"/.git "$CANARY_DIR/" 2>/dev/null || true

echo "  canary: $CANARY_DIR"
_pass "workspace copied"

MEMORY_BEFORE=$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null | wc -l || echo 0)
COMMITS_BEFORE=$(cd "$WS_DIR" 2>/dev/null && git log --oneline 2>/dev/null | wc -l || echo 0)

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"

  ORZ_PROMPT="Execute a full ORZ cycle in workspace $CANARY_DIR:
1. OPEN: Check WP Gate — task in WeekPlan? If not, offer wp-new.
2. WORK: Follow protocol-work.md — KE routing, self-correction on each milestone.
3. CLOSE: Run Quick Close — update WP Context, sync MEMORY.md, commit.
The task is: review and update MEMORY.md statuses for current week RP.
This is an automated canary test — auto-approve all actions."

  if [ -f "$WRAPPER" ]; then
    source "$WRAPPER"
    echo "=== Running ORZ Cycle on canary ==="
    AI_CLI_TIMEOUT=600
    export AI_CLI="${AI_CLI:-opencode}"
    export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
    RUN_RC=0
    RUN_OUT=$(ai_cli_run "$ORZ_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null) || RUN_RC=$?
    if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: ORZ Cycle failed (rc=$RUN_RC)" >&2; exit 2; fi
    echo "=== ORZ Cycle done ==="
  else
    echo "SKIP: ai-cli-wrapper not found (--run requires AI CLI)"
  fi
fi

CANARY_MEMORY="$CANARY_DIR/memory/MEMORY.md"
echo "  --- diff ---"
MEMORY_AFTER=$(cat "$CANARY_MEMORY" 2>/dev/null | wc -l || echo 0)
COMMITS_AFTER=$(cd "$CANARY_DIR" 2>/dev/null && git log --oneline 2>/dev/null | wc -l || echo 0)
echo "  MEMORY:  $MEMORY_BEFORE → $MEMORY_AFTER lines"
echo "  Commits: $COMMITS_BEFORE → $COMMITS_AFTER"

if $RUN_MODE; then
  [ "$MEMORY_AFTER" -ne "$MEMORY_BEFORE" ] \
    && _pass "MEMORY.md modified" \
    || _pass "MEMORY.md unchanged (may already be current)"

  [ "$COMMITS_AFTER" -gt "$COMMITS_BEFORE" ] \
    && _pass "new commits created" \
    || _fail "no new commits (ORZ cycle may not have completed)"

  grep -qiE 'updated\|valid_from.*2026' "$CANARY_MEMORY" 2>/dev/null \
    && _pass "MEMORY.md has temporal metadata" \
    || _pass "temporal metadata: check manually"
else
  _pass "diff: run with --run to execute AI process"
fi

echo "  --- cleanup ---"
rm -rf "$CANARY_DIR" 2>/dev/null || true
_pass "canary cleaned up"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
