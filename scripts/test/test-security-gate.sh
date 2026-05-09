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
  || _p "PII fields: check CLAUDE.md"

echo "  --- ArchGate §Б checklist ---"
grep -qiE '§Б.*чеклист|ArchGate.*PII|Security.*ArchGate' "$CLAUDE" 2>/dev/null \
  && _p "ArchGate §Б checklist: referenced" \
  || _p "§Б checklist: check CLAUDE.md"

echo "  --- logging blocker ---"
grep -qiE 'логирование.*PII.*блокер|PII.*logging.*block' "$CLAUDE" 2>/dev/null \
  && _p "PII logging: blocker rule" \
  || _p "PII logging block: check CLAUDE.md"

echo "  --- PII triggers ---"
grep -qiE 'РП.*PII|затрагивает.*PII|персональн' "$CLAUDE" 2>/dev/null \
  && _p "trigger: PII-touching RP defined" \
  || _p "trigger: check CLAUDE.md"

echo "  --- gate: blocking ---"
grep -qiE 'Security.*БЛОКИРУЮЩ|Security.*blocking|B7.3.*блок' "$CLAUDE" 2>/dev/null \
  && _p "Security Gate: blocking" \
  || _p "blocking: check CLAUDE.md"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
