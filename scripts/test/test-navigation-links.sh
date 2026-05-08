#!/usr/bin/env bash
# test-navigation-links.sh — navigation.md path resolution (§14, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

NAV="$ROOT_DIR/persistent-memory/navigation.md"

echo "  --- navigation.md link resolution ---"
[ -f "$NAV" ] || { _fail "navigation.md not found"; exit $FAIL; }

# Extract @-references: `@./path/to/file`
refs=$(grep -oP '@\.(/[a-zA-Z0-9_/.-]+)' "$NAV" 2>/dev/null || true)
resolved=0 broken=0

while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  ref="${ref#@}"  # strip @
  path="$ROOT_DIR/${ref#./}"  # ./foo → $ROOT_DIR/foo
  if [ -f "$path" ] || [ -d "$path" ]; then
    resolved=$((resolved + 1))
  else
    _fail "broken link: $ref → $path"
    broken=$((broken + 1))
  fi
done <<< "$refs"

echo "  links: $resolved resolved, $broken broken"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL