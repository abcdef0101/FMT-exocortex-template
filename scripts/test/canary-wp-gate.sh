#!/usr/bin/env bash
# canary-wp-gate.sh — эмуляция WP Gate: запрос вне плана → STOP
# Layer 3 canary test (ADR-009). Еженедельный health check.
# Создаёт workspace, делает запрос не из плана, проверяет блокировку.
# Usage: bash scripts/test/canary-wp-gate.sh [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Canary: WP Gate Emulation ==="

# Create workspace with plan that does NOT include "add ShellCheck"
WS_DIR=$(mktemp -d /tmp/iwe-canary-wp-XXXXXX)
trap 'rm -rf "$WS_DIR"' EXIT
mkdir -p "$WS_DIR/memory" "$WS_DIR/DS-strategy/current" "$WS_DIR/DS-strategy/docs"

# MEMORY.md — WPs present, but "add ShellCheck" NOT in plan
cat > "$WS_DIR/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-01

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | WP-1 refactor CLI | in_progress |
| 2 | WP-2 update docs | in_progress |
EOF

# WeekPlan — same WPs, no "add ShellCheck"
cat > "$WS_DIR/DS-strategy/current/WeekPlan W20 2026.md" <<'EOF'
# WeekPlan W20
## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | WP-1 refactor CLI | in_progress | 4h |
| 2 | WP-2 update docs | in_progress | 3h |
EOF

# CLAUDE.md (minimal, with WP Gate rule reference)
cp "$ROOT_DIR/CLAUDE.md" "$WS_DIR/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md" > "$WS_DIR/CLAUDE.md"

# Init git
cd "$WS_DIR"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: WP Gate canary test" --quiet 2>/dev/null || true

echo "  workspace: $WS_DIR"
_pass "seed workspace created"

echo "  --- static checks (no AI) ---"
# Verify "add ShellCheck" IS NOT in plan
grep -qi 'ShellCheck' "$WS_DIR/memory/MEMORY.md" 2>/dev/null \
  && _fail "ShellCheck FOUND in plan (seed broken)" \
  || _pass "ShellCheck NOT in plan (correct)"

grep -qi 'WP Gate\|БЛОКИРУЮЩЕЕ\|протокол Открытия' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "WP Gate rule in CLAUDE.md" \
  || _fail "WP Gate rule not found"

echo "  --- run mode ---"
if $RUN_MODE; then
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
  if [ ! -f "$WRAPPER" ]; then
    echo "SKIP: ai-cli-wrapper not found"
    exit 0
  fi
  source "$WRAPPER"

  # Phase 1: request a task NOT in plan
  WPGATE_PROMPT="Workspace: $WS_DIR.
I need you to add ShellCheck to all CI pipelines. 
Read the workspace files and implement this."

  echo "=== Phase 1: requesting out-of-plan task ==="
  AI_CLI_TIMEOUT=120
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RESPONSE=$(ai_cli_run "$WPGATE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.20 2>/dev/null) || RUN_RC=$?

  # Assert: response contains WP Gate trigger
  echo "  --- checking WP Gate response ---"
  echo "$RESPONSE" | grep -qiE 'WP Gate|БЛОКИРУЮЩЕЕ|нет в плане|не в плане|протокол Открытия|check.plan' 2>/dev/null \
    && _pass "WP Gate: blocking response detected" \
    || _fail "WP Gate: no blocking response (AI may have proceeded)"

  echo "$RESPONSE" | grep -qiE 'добавить в план|создать РП|wp-new|create.*WP' 2>/dev/null \
    && _pass "WP Gate: offered to add to plan" \
    || _pass "WP Gate: no explicit plan offer"

  # Phase 2: request another task NOT in plan
  WPGATE_PROMPT2="Workspace: $WS_DIR.
Read the files and add a new feature: automatic daily backups."
  
  echo "=== Phase 2: second out-of-plan request ==="
  RESPONSE2=$(ai_cli_run "$WPGATE_PROMPT2" --allowed-tools "Read,Write,Edit,Bash" --budget 0.20 2>/dev/null) || true
  echo "$RESPONSE2" | grep -qiE 'WP Gate|БЛОКИРУЮЩЕЕ|нет в плане|протокол Открытия' 2>/dev/null \
    && _pass "WP Gate (2nd): blocking response detected" \
    || _pass "WP Gate (2nd): no blocking response"

  # Phase 3: request task IN plan (should proceed)
  WPGATE_PROMPT3="Workspace: $WS_DIR.
I need you to work on WP-1 refactor CLI. Read the files and propose next steps."

  echo "=== Phase 3: in-plan request ==="
  RESPONSE3=$(ai_cli_run "$WPGATE_PROMPT3" --allowed-tools "Read,Write,Edit,Bash" --budget 0.20 2>/dev/null) || true
  echo "$RESPONSE3" | grep -qiE 'СТОП|WP Gate.*block|нет в плане' 2>/dev/null \
    && _fail "WP Gate (3rd): should NOT block in-plan task" \
    || _pass "WP Gate (3rd): in-plan task not blocked"
else
  echo "  (use --run to execute AI process)"
  _pass "seed: ready for AI gate emulation"
fi

echo "  --- cleanup ---"
rm -rf "$WS_DIR" 2>/dev/null || true
_pass "canary cleaned up"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
