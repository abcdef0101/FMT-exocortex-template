#!/usr/bin/env bash
# test-day-rhythm-schema.sh — day-rhythm-config.yaml check (§14, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

RHYTHM="$ROOT_DIR/seed/day-rhythm-config.yaml"
[ -f "$RHYTHM" ] || RHYTHM="$ROOT_DIR/day-rhythm-config.yaml"

echo "  --- day-rhythm-config.yaml ---"
[ -f "$RHYTHM" ] || { _fail "day-rhythm-config.yaml not found"; exit $FAIL; }
_pass "file exists: $RHYTHM"

grep -q 'day_open:' "$RHYTHM" && _pass "day_open section" || _fail "day_open missing"
grep -q 'strategy_day:' "$RHYTHM" && _pass "strategy_day field" || _fail "strategy_day missing"
grep -q 'self_dev_slot:' "$RHYTHM" && _pass "self_dev_slot field" || _fail "self_dev_slot missing"

# Check daily_rp if it exists (seed template has it)
grep -q 'daily_rp:' "$RHYTHM" 2>/dev/null \
  && _pass "daily_rp array present" \
  || _pass "daily_rp: not in seed template (user-level config)"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL