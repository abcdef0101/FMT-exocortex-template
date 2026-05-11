#!/usr/bin/env bash
# test-params-schema.sh — params.yaml schema check (§14, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

PARAMS="$ROOT_DIR/seed/params.yaml"
[ -f "$PARAMS" ] || PARAMS="$ROOT_DIR/params.yaml"

echo "  --- params.yaml ---"
[ -f "$PARAMS" ] || { _fail "params.yaml not found"; exit $FAIL; }
_pass "params.yaml: $PARAMS"

# params.yaml keys can be commented (seed template) or active (user config)
# Check they are at least mentioned
for section in author_mode extensions; do
  if grep -q "$section" "$PARAMS" 2>/dev/null; then
    _pass "section mentioned: $section"
  else
    _fail "section missing: $section"
  fi
done

for section in schedule purpose pomodoro; do
  if grep -q "$section" "$PARAMS" 2>/dev/null; then
    _pass "section mentioned: $section"
  else
    _pass "section not in template: $section (user-level config)"
  fi
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL