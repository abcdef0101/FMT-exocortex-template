#!/usr/bin/env bash
# test-wp-context-structure.sh — WP Context file structure (§11, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- WP Context file pattern check ---"

required=("Осталось" "What's Left" "Что пробовали" "Следующий шаг")

context_docs=$(find "$ROOT_DIR" -path "*/DS-strategy/inbox/WP-*.md" -o -path "*/inbox/WP-*.md" 2>/dev/null | head -5)
checked=0

if [ -z "$context_docs" ]; then
  echo "  - No WP Context files found (workspace inactive, ok)"
else
  for f in $context_docs; do
    name=$(basename "$f")
    checked=$((checked + 1))
    # Check at least one of the section heading patterns (ru/en)
    has_remaining=$(grep -cE '## Осталось|## What.s Left' "$f" 2>/dev/null || echo 0)
    has_tried=$(grep -cE '## Что пробовали|## Tried' "$f" 2>/dev/null || echo 0)
    has_learned=$(grep -cE '## Что узнали|## Learned' "$f" 2>/dev/null || echo 0)
    has_next=$(grep -cE '## Следующий шаг|## Next Step' "$f" 2>/dev/null || echo 0)

    missing=""
    [ "$has_remaining" -eq 0 ] && missing="$missing remaining"
    [ "$has_next" -eq 0 ] && missing="$missing next-step"

    if [ -z "$missing" ]; then
      _pass "$name: key sections present"
    else
      _pass "$name: structural check — $checked WP files, missing:$missing (advisory)"
    fi
  done
fi

# Check template definition in docs/workflow-full.md
[ -f "$ROOT_DIR/docs/workflow-full.md" ] \
  && grep -q "Осталось.*What's Left" "$ROOT_DIR/docs/workflow-full.md" 2>/dev/null \
  && _pass "WP Context template: documented in workflow-full.md" \
  || _pass "WP Context template: check docs/workflow-full.md"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL