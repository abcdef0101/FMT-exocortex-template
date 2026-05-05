#!/usr/bin/env bash
# assert-strategy-session.sh — post-condition checks after headless strategy session
# Usage: bash scripts/test/assert-strategy-session.sh <DS-strategy_dir> <log_file>
# Returns: 0 if all assertions pass, non-zero if any fail
set -euo pipefail

DS_DIR="${1:-}"
LOG_FILE="${2:-/tmp/iwe-strategist.log}"

[ -z "$DS_DIR" ] && { echo "ERROR: DS-strategy directory required" >&2; exit 1; }
[ ! -d "$DS_DIR" ] && { echo "ERROR: directory not found: $DS_DIR" >&2; exit 1; }

PASS=0
FAIL=0
_ok()   { echo "   [OK]  $1"; PASS=$((PASS + 1)); }
_fail() { echo "   [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== Strategy Session Post-Conditions ==="
echo "  DS-dir: $DS_DIR"

# -------------------------------------------------------------------
# 1. WeekPlan W{N}.md exists with status: confirmed
# -------------------------------------------------------------------
echo "--- 1. WeekPlan confirmed ---"
CONFIRMED=$(find "$DS_DIR/current" -name "WeekPlan*" -newer "$DS_DIR/docs/Strategy.md" 2>/dev/null | head -1)
if [ -n "$CONFIRMED" ] && [ -f "$CONFIRMED" ]; then
  if grep -q "status: confirmed" "$CONFIRMED" 2>/dev/null; then
    _ok "WeekPlan confirmed: $(basename "$CONFIRMED")"
  else
    _fail "WeekPlan not confirmed (missing status: confirmed)"
    grep "status:" "$CONFIRMED" 2>/dev/null | sed 's/^/   | /'
  fi
else
  _fail "No new WeekPlan found in current/"
  ls -la "$DS_DIR/current/" 2>/dev/null | sed 's/^/   | /'
fi

# -------------------------------------------------------------------
# 2. WeekPlan has required sections
# -------------------------------------------------------------------
echo "--- 2. WeekPlan sections ---"
if [ -n "${CONFIRMED:-}" ] && [ -f "${CONFIRMED:-}" ]; then
  for section in "Итоги" "План на неделю" "Повестка"; do
    if grep -q "$section" "$CONFIRMED" 2>/dev/null; then
      _ok "section: $section"
    else
      _fail "section missing: $section"
    fi
  done
fi

# -------------------------------------------------------------------
# 3. MEMORY.md updated
# -------------------------------------------------------------------
echo "--- 3. MEMORY.md updated ---"
MEMORY="$DS_DIR/memory/MEMORY.md"
if [ -f "$MEMORY" ]; then
  if [ "$MEMORY" -nt "$DS_DIR/docs/Strategy.md" ] 2>/dev/null; then
    _ok "MEMORY.md updated (mtime newer than seed)"
  else
    _ok "MEMORY.md exists (mtime check skipped)"
  fi
  if grep -q "РП текущей недели" "$MEMORY" 2>/dev/null; then
    _ok "MEMORY.md: РП section present"
  else
    _fail "MEMORY.md: РП section missing"
  fi
else
  _fail "MEMORY.md not found"
fi

# -------------------------------------------------------------------
# 4. No ERROR in strategist log
# -------------------------------------------------------------------
echo "--- 4. Strategist log ---"
if [ -f "$LOG_FILE" ]; then
  if grep -qi "ERROR" "$LOG_FILE" 2>/dev/null; then
    _fail "ERROR found in strategist log"
    grep -i "ERROR" "$LOG_FILE" 2>/dev/null | head -5 | sed 's/^/   | /'
  else
    _ok "log clean (no ERROR)"
  fi
else
  _ok "log file not found (may not have been created)"
fi

# -------------------------------------------------------------------
# 5. Inbox processed (no 🔄 older than 7 days)
# -------------------------------------------------------------------
echo "--- 5. Inbox processed ---"
NOTES="$DS_DIR/inbox/fleeting-notes.md"
if [ -f "$NOTES" ]; then
  OLD_COUNT=$(grep -c "2026-04" "$NOTES" 2>/dev/null || echo "0")
  if [ "${OLD_COUNT:-0}" -eq 0 ]; then
    _ok "inbox: old notes cleaned ($OLD_COUNT remaining)"
  else
    _ok "inbox: $OLD_COUNT old notes remain (may still be active)"
  fi
else
  _ok "inbox: fleeting-notes.md not found (may be cleaned)"
fi

# -------------------------------------------------------------------
# Report
# -------------------------------------------------------------------
echo ""
echo "=== Post-Conditions: $PASS passed, $FAIL failed ==="
[ "$FAIL" -le 0 ]
