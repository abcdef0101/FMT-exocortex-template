#!/usr/bin/env bash
# test-adr-structure.sh — ADR document structure check (§15, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ADR_DIR="$ROOT_DIR/docs/adr"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- ADR files ---"

adr_count=0
while IFS= read -r -d '' f; do
  [[ "$f" == *"/impl/"* ]] && continue
  name=$(basename "$f")
  adr_count=$((adr_count + 1))

  has_context=$(grep -c '## Context\|## Контекст' "$f" 2>/dev/null || echo 0)
  has_decision=$(grep -c '## Decision\|## Решение' "$f" 2>/dev/null || echo 0)
  has_consequences=$(grep -c '## Consequences\|## Последствия' "$f" 2>/dev/null || echo 0)
  has_status=$(grep -c '## Status\|## Статус' "$f" 2>/dev/null || echo 0)

  missing=""
  [ "$has_context" -eq 0 ] && missing="$missing Context"
  [ "$has_decision" -eq 0 ] && missing="$missing Decision"
  [ "$has_consequences" -eq 0 ] && missing="$missing Consequences"
  [ "$has_status" -eq 0 ] && missing="$missing Status"

  if [ -z "$missing" ]; then
    _pass "$name: all sections present"
  else
    _fail "$name: missing sections:$missing"
  fi
done < <(find "$ADR_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null || true)

echo "  ADRs: $adr_count found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL