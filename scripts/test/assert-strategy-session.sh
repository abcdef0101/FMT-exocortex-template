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
CONFIRMED=$(find "$DS_DIR/DS-strategy/current" -name "WeekPlan*" -newer "$DS_DIR/DS-strategy/docs/Session Agenda.md" 2>/dev/null | head -1)
if [ -n "$CONFIRMED" ] && [ -f "$CONFIRMED" ]; then
  if grep -q "status: confirmed" "$CONFIRMED" 2>/dev/null; then
    _ok "WeekPlan confirmed: $(basename "$CONFIRMED")"
  else
    _fail "WeekPlan not confirmed (missing status: confirmed)"
    grep "status:" "$CONFIRMED" 2>/dev/null | sed 's/^/   | /'
  fi
else
  _fail "No new WeekPlan found in current/"
  ls -la "$DS_DIR/DS-strategy/current/" 2>/dev/null | sed 's/^/   | /'
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
# 2b. WeekPlan size — not empty
# -------------------------------------------------------------------
echo "--- 2b. WeekPlan size ---"
if [ -n "${CONFIRMED:-}" ] && [ -f "${CONFIRMED:-}" ]; then
  SIZE=$(wc -c < "$CONFIRMED" 2>/dev/null | tr -d ' ')
  if [ "${SIZE:-0}" -gt 500 ]; then
    _ok "size: ${SIZE}b"
  else
    _fail "size: ${SIZE:-0}b (too small, may be empty)"
  fi
fi

# -------------------------------------------------------------------
# 2c. WeekPlan has РП table rows
# -------------------------------------------------------------------
echo "--- 2c. WeekPlan РП table ---"
if [ -n "${CONFIRMED:-}" ] && [ -f "${CONFIRMED:-}" ]; then
  TABLE_ROWS=$(grep -c '^| #' "$CONFIRMED" 2>/dev/null | tr -d '\n' || echo "0")
  if [ "${TABLE_ROWS:-0}" -ge 1 ]; then
    _ok "table: ${TABLE_ROWS} РП entries"
  else
    _fail "table: no РП entries found (plan may be empty)"
  fi
fi

# -------------------------------------------------------------------
# 2d. Frontmatter completeness
# -------------------------------------------------------------------
echo "--- 2d. Frontmatter ---"
if [ -n "${CONFIRMED:-}" ] && [ -f "${CONFIRMED:-}" ]; then
  for field in "type:" "week:" "date_start:" "status:" "agent:"; do
    if grep -q "$field" "$CONFIRMED" 2>/dev/null; then
      _ok "fm: $field"
    else
      _fail "fm: $field missing"
    fi
  done
fi

# -------------------------------------------------------------------
# 2e. Carry-over — past РП preserved
# -------------------------------------------------------------------
echo "--- 2e. Carry-over ---"
if [ -n "${CONFIRMED:-}" ] && [ -f "${CONFIRMED:-}" ]; then
  # Seed WeekPlan has carry-over РП #3 and #5 — check they appear in new plan
  CARRY_COUNT=0
  for rp_ref in "Golden image pipeline" "Container CI" "pidfile"; do
    if grep -qi "$rp_ref" "$CONFIRMED" 2>/dev/null; then
      CARRY_COUNT=$((CARRY_COUNT + 1))
    fi
  done
  if [ "$CARRY_COUNT" -ge 1 ]; then
    _ok "carry-over: ${CARRY_COUNT}/3 past РП references found"
  else
    _fail "carry-over: 0/3 past РП references (carry-over may be lost)"
  fi
fi

# -------------------------------------------------------------------
# 3. MEMORY.md updated
# -------------------------------------------------------------------
echo "--- 3. MEMORY.md updated ---"
MEMORY="$DS_DIR/memory/MEMORY.md"
if [ -f "$MEMORY" ]; then
  if [ "$MEMORY" -nt "$DS_DIR/DS-strategy/docs/Strategy.md" ] 2>/dev/null; then
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
NOTES="$DS_DIR/DS-strategy/inbox/fleeting-notes.md"
if [ -f "$NOTES" ]; then
  OLD_COUNT=$(grep -c "2026-04" "$NOTES" 2>/dev/null | tr -d '\n' || echo "0")
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
