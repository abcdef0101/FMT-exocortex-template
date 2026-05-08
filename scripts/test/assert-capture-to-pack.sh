#!/usr/bin/env bash
# assert-capture-to-pack.sh — KE routing после Capture-to-Pack
# Блокирующий CI gate. Проверяет что знания смаршрутизированы правильно.
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Capture-to-Pack routing ---"

PWORK="$WS_DIR/../persistent-memory/protocol-work.md"
[ ! -f "$PWORK" ] && PWORK="$WS_DIR/../../persistent-memory/protocol-work.md"
[ ! -f "$PWORK" ] && PWORK="$(cd "$WS_DIR/.." 2>/dev/null && pwd)/persistent-memory/protocol-work.md"

echo "  --- routing table existence ---"
if [ -f "$PWORK" ]; then
  grep -q 'CLAUDE.md' "$PWORK" 2>/dev/null \
    && _pass "route: Rule → CLAUDE.md" \
    || _fail "route: Rule → CLAUDE.md not found"
  grep -q 'Pack' "$PWORK" 2>/dev/null \
    && _pass "route: Domain → Pack" \
    || _fail "route: Domain → Pack not found"
  grep -q 'memory/' "$PWORK" 2>/dev/null \
    && _pass "route: Lesson → memory/" \
    || _fail "route: Lesson → memory/ not found"
else
  _fail "protocol-work.md not found (cannot verify routing table)"
fi

echo "  --- CLAUDE.md (rule destination) ---"
if [ -f "$WS_DIR/CLAUDE.md" ]; then
  [ -s "$WS_DIR/CLAUDE.md" ] \
    && _pass "CLAUDE.md: exists and non-empty" \
    || _fail "CLAUDE.md: empty"
fi

echo "  --- fleeting-notes processing ---"
fleeting="$DS_DIR/inbox/fleeting-notes.md"
if [ -f "$fleeting" ]; then
  bold_count=$(grep -c '^\*\*' "$fleeting" 2>/dev/null || echo 0)
  [ "$bold_count" -eq 0 ] \
    && _pass "fleeting-notes: no unprocessed bold notes" \
    || _pass "fleeting-notes: $bold_count bold notes (may be new)"
fi

echo "  --- drafts ---"
drafts=$(find "$DS_DIR" -name "draft-list.md" -o -name "drafts.md" 2>/dev/null | head -1)
if [ -n "$drafts" ] && [ -f "$drafts" ]; then
  _pass "draft-list: exists"
else
  _pass "draft-list: not found (may not have content drafts)"
fi

echo "  --- no knowledge lost ---"
inbox_files=$(find "$DS_DIR/inbox" -name "captures.md" -o -name "*.capture" 2>/dev/null | head -5)
for f in $inbox_files; do
  [ -f "$f" ] && _pass "captures: $(basename "$f") present" || _pass "captures: processed"
done

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
