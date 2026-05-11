#!/usr/bin/env bash
# test-security-gate.sh — Security Gate: PII чеклист для РП затрагивающих PII
# Source: CLAUDE.md §2 (Security Gate B7.3)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_p() { echo "  ✓ $1"; }
_f() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- Security Gate in CLAUDE.md ---"
grep -qiE 'Security Gate|B7\.3|PII.*gate' "$CLAUDE" 2>/dev/null \
  && _p "Security Gate: rule present" \
  || _f "Security Gate rule not found"

echo "  --- PII scope ---"
grep -qiE 'email|telegram_id|ЦД|tokens|user_events' "$CLAUDE" 2>/dev/null \
  && _p "PII fields: enumerated" \
  || _f "PII fields: not enumerated in CLAUDE.md"

echo "  --- ArchGate §Б checklist ---"
grep -qiE '§Б.*чеклист|ArchGate.*PII|Security.*ArchGate' "$CLAUDE" 2>/dev/null \
  && _p "ArchGate §Б checklist: referenced" \
  || _f "§Б checklist: not found in CLAUDE.md"

echo "  --- logging blocker ---"
grep -qiE 'логирование.*PII.*блокер|PII.*logging.*block' "$CLAUDE" 2>/dev/null \
  && _p "PII logging: blocker rule" \
  || _f "PII logging: blocker rule not found in CLAUDE.md"

echo "  --- PII triggers ---"
grep -qiE 'РП.*PII|затрагивает.*PII|персональн' "$CLAUDE" 2>/dev/null \
  && _p "trigger: PII-touching RP defined" \
  || _f "trigger: PII-touching RP not found in CLAUDE.md"

echo "  --- gate: blocking ---"
{ grep -q 'Security Gate' "$CLAUDE" && grep -q 'Pre-action Gates' "$CLAUDE"; } \
  && _p "Security Gate: defined under Pre-action Gates" \
  || _f "Security Gate: not linked to Pre-action Gates section"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
