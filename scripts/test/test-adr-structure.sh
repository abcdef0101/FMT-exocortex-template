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

  has_context=$(grep -ciE '## Context|## Контекст|\*\*Контекст|\*\*Context' "$f" 2>/dev/null || true)
  has_context=${has_context:-0}
  has_decision=$(grep -ciE '## Decision|## Решение|\*\*Решение|\*\*Decision' "$f" 2>/dev/null || true)
  has_decision=${has_decision:-0}
  has_consequences=$(grep -ciE '## Consequences|## Последствия|\*\*Последстви|\*\*Consequences' "$f" 2>/dev/null || true)
  has_consequences=${has_consequences:-0}
  has_status=$(grep -ciE '## Status|## Статус|\*\*Статус|\*\*Status|\>.*Status' "$f" 2>/dev/null || true)
  has_status=${has_status:-0}

  missing=""
  [ "$has_context" -eq 0 ] 2>/dev/null && missing="$missing Context"
  [ "$has_decision" -eq 0 ] 2>/dev/null && missing="$missing Decision"
  [ "$has_consequences" -eq 0 ] 2>/dev/null && missing="$missing Consequences"
  [ "$has_status" -eq 0 ] 2>/dev/null && missing="$missing Status"

  if [ -z "$missing" ]; then
    _pass "$name: all sections present"
  else
    _fail "$name: missing sections:$missing"
  fi
done < <(find "$ADR_DIR" -maxdepth 1 -name "ADR-*.md" -type f -print0 2>/dev/null || true)

echo "  ADRs: $adr_count found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL