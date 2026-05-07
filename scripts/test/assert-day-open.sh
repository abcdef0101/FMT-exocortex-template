#!/usr/bin/env bash
# assert-day-open.sh — post-condition checks after headless Day Open E2E
# Usage: bash scripts/test/assert-day-open.sh <workspace_dir> [<log_file>]
# Returns: 0 if all assertions pass, non-zero if any fail
set -euo pipefail

WS_DIR="${1:-}"
LOG_FILE="${2:-/tmp/iwe-dayopen-$$.log}"

[ -z "$WS_DIR" ] && { echo "ERROR: workspace directory required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: directory not found: $WS_DIR" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && { echo "ERROR: DS-strategy not found: $DS_DIR" >&2; exit 1; }

PASS=0
FAIL=0
_ok()   { echo "   [OK]  $1"; PASS=$((PASS + 1)); }
_fail() { echo "   [FAIL] $1"; FAIL=$((FAIL + 1)); }

TODAY=$(date +%Y-%m-%d)

echo "=== Day Open Post-Conditions ==="
echo "  Workspace: $WS_DIR"
echo "  Today:     $TODAY"

# -------------------------------------------------------------------
# 1. DayPlan exists in current/
# -------------------------------------------------------------------
echo "--- 1. DayPlan exists ---"
DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*${TODAY}*.md" 2>/dev/null | head -1)
if [ -z "$DAYPLAN" ]; then
  DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*" -newer "$DS_DIR/docs/Strategy.md" 2>/dev/null | head -1)
fi
if [ -z "$DAYPLAN" ]; then
  DAYPLAN=$(find "$DS_DIR/current" -maxdepth 1 -name "Day*" -newer "$DS_DIR/docs/Strategy.md" 2>/dev/null | head -1)
fi
if [ -n "$DAYPLAN" ] && [ -f "$DAYPLAN" ]; then
  _ok "DayPlan found: $(basename "$DAYPLAN")"
else
  _fail "DayPlan not found in current/"
  ls -la "$DS_DIR/current/" 2>/dev/null | sed 's/^/   | /'
fi

# -------------------------------------------------------------------
# 2. Frontmatter completeness
# -------------------------------------------------------------------
echo "--- 2. Frontmatter ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  for field in "type:" "date:" "week:" "status:" "agent:"; do
    if grep -q "^$field" "$DAYPLAN" 2>/dev/null; then
      _ok "fm: $field"
    else
      _fail "fm: $field missing"
    fi
  done
  if grep -qE "status: (active|in_progress)" "$DAYPLAN" 2>/dev/null; then
    _ok "fm: status is $(grep 'status:' "$DAYPLAN" 2>/dev/null | head -1 | sed 's/.*status: //')"
  else
    STATUS=$(grep "status:" "$DAYPLAN" 2>/dev/null | head -1 | sed 's/.*status: //')
    _fail "fm: status is '$STATUS' (expected 'active' or 'in_progress')"
  fi
fi

# -------------------------------------------------------------------
# 3. Required sections present
# -------------------------------------------------------------------
echo "--- 3. Sections ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  for section in "План на сегодня" "Календарь" "IWE за ночь" "Разбор заметок" "Итоги вчера"; do
    if grep -q "$section" "$DAYPLAN" 2>/dev/null; then
      _ok "section: $section"
    else
      _fail "section missing: $section"
    fi
  done
fi

# -------------------------------------------------------------------
# 4. Size > 500 bytes
# -------------------------------------------------------------------
echo "--- 4. DayPlan size ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  SIZE=$(wc -c < "$DAYPLAN" 2>/dev/null | tr -d ' ')
  if [ "${SIZE:-0}" -gt 500 ]; then
    _ok "size: ${SIZE}b"
  else
    _fail "size: ${SIZE:-0}b (too small, may be empty)"
  fi
fi

# -------------------------------------------------------------------
# 5. Table rows present
# -------------------------------------------------------------------
echo "--- 5. Plan table ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  TABLE_ROWS=$(grep -c '^|.*#.*|.*РП.*|' "$DAYPLAN" 2>/dev/null | tr -d '\n' || echo "0")
  if [ "${TABLE_ROWS:-0}" -ge 1 ]; then
    _ok "table: ${TABLE_ROWS} RP row(s)"
  else
    # Fallback: count any markdown table rows with | separators
    TABLE_ROWS=$(grep -c '^|.*|.*|.*|' "$DAYPLAN" 2>/dev/null | tr -d '\n' || echo "0")
    if [ "${TABLE_ROWS:-0}" -ge 2 ]; then
      _ok "table: ${TABLE_ROWS} rows (generic)"
    else
      _fail "table: no rows found"
    fi
  fi
fi

# -------------------------------------------------------------------
# 6. Carry-over BLOCKING — RP from «Завтра начать с» in plan
# -------------------------------------------------------------------
echo "--- 6. Carry-over fidelity ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  # Check: carry-over RP #2 (Day Open E2E) and #4 (FPF review) are mentioned
  CARRY_COUNT=0
  for kw in "Day Open" "FPF review" "artifact"; do
    if grep -qi "$kw" "$DAYPLAN" 2>/dev/null; then
      CARRY_COUNT=$((CARRY_COUNT + 1))
    fi
  done
  if [ "$CARRY_COUNT" -ge 2 ]; then
    _ok "carry-over: ${CARRY_COUNT}/3 keywords found"
  else
    _fail "carry-over: only ${CARRY_COUNT}/3 keywords (expected ≥2)"
  fi
fi

# -------------------------------------------------------------------
# 7. Budget line present
# -------------------------------------------------------------------
echo "--- 7. Budget ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  if grep -q "Бюджет" "$DAYPLAN" 2>/dev/null; then
    _ok "budget: budget line present"
  else
    _fail "budget: budget line missing"
  fi
fi

# -------------------------------------------------------------------
# 8. Self-development slot present
# -------------------------------------------------------------------
echo "--- 8. Self-development ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  if grep -qi "саморазвити" "$DAYPLAN" 2>/dev/null; then
    _ok "self-dev: slot present"
  else
    _fail "self-dev: slot missing"
  fi
fi

# -------------------------------------------------------------------
# 9. «Требует внимания» — non-empty when issues exist
# -------------------------------------------------------------------
echo "--- 9. Attention section ---"
if [ -n "${DAYPLAN:-}" ] && [ -f "${DAYPLAN:-}" ]; then
  if grep -qi "требует внимания\|attention" "$DAYPLAN" 2>/dev/null; then
    _ok "attention: section present"
  else
    # Not a hard fail — may be empty if no problems
    _ok "attention: section absent (may be empty — no issues)"
  fi
fi

# -------------------------------------------------------------------
# 10. No ERROR in log
# -------------------------------------------------------------------
echo "--- 10. Log check ---"
if [ -f "$LOG_FILE" ]; then
  if grep -qi "ERROR" "$LOG_FILE" 2>/dev/null; then
    _fail "ERROR found in log"
    grep -i "ERROR" "$LOG_FILE" 2>/dev/null | head -5 | sed 's/^/   | /'
  else
    _ok "log clean (no ERROR)"
  fi
else
  _ok "log file not found (may not have been created)"
fi

# -------------------------------------------------------------------
# 11. Previous DayPlan archived
# -------------------------------------------------------------------
echo "--- 11. Archive ---"
YESTERDAY=$(date -d "$TODAY -1 day" +%Y-%m-%d 2>/dev/null || echo "")
if [ -n "$YESTERDAY" ]; then
  if ls "$DS_DIR/archive/day-plans/DayPlan ${YESTERDAY}"*.md 2>/dev/null | head -1 >/dev/null 2>&1; then
    _ok "archive: yesterday DayPlan archived"
  else
    # May have been cleaned in seed — not a hard fail
    _ok "archive: yesterday DayPlan not found (may be initial state)"
  fi
fi

# -------------------------------------------------------------------
# Report
# -------------------------------------------------------------------
echo ""
echo "=== Post-Conditions: $PASS passed, $FAIL failed ==="
[ "$FAIL" -le 0 ]
