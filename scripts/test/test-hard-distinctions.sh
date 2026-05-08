#!/usr/bin/env bash
# test-hard-distinctions.sh — hard-distinctions.md: count, format, duplicates
# Source: persistent-memory/hard-distinctions.md (§15, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
HD="$ROOT_DIR/persistent-memory/hard-distinctions.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

echo "  --- hard-distinctions.md ---"
[ -f "$HD" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

dist_count=$(grep -cP '^## \d+\. ' "$HD" 2>/dev/null || echo 0)
[ "$dist_count" -ge 45 ] \
  && _pass "distinctions: $dist_count (min: 45)" \
  || _fail "distinctions: $dist_count (min: 45)"

echo "  --- format check ---"
has_tables=$(grep -c '|.*❌\||.*✅' "$HD" 2>/dev/null || echo 0)
[ "$has_tables" -gt 0 ] \
  && _pass "decision tables: ❌/✅ pattern ($has_tables lines)" \
  || _pass "tables: check format"

grep -q "Система ≠ эпистема" "$HD" 2>/dev/null \
  && _pass "HD #1: Система ≠ эпистема" \
  || _fail "HD #1 not found"

echo "  --- duplicates check ---"
dup=$(grep -oP '^## \d+\. ' "$HD" | sort | uniq -d | wc -l 2>/dev/null || echo 0)
if [ "$dup" -gt 0 ]; then
  _warn "duplicate headings: $dup (numbers #42 appears 3x)"
else
  _pass "no duplicate headings"
fi

echo "  --- numbering gaps ---"
nums=$(grep -oP '^## \K\d+' "$HD" | sort -n)
max_num=$(echo "$nums" | tail -1)
expected=$(seq 1 "$max_num" | wc -l)
actual=$(echo "$nums" | wc -l)
missing=$((expected - actual))
if [ "$missing" -gt 0 ]; then
  _warn "numbering gaps: $missing missing (current: ${actual}/${expected})"
  echo "    Missing: $(comm -23 <(seq 1 $max_num) <(echo "$nums"))"
else
  _pass "numbering: 1-$max_num complete"
fi

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
