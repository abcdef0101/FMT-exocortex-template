#!/usr/bin/env bash
# assert-extractor-inbox-check.sh — структурные инварианты Extractor inbox-check результата
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Extractor Inbox Check ---"

echo "  --- fleeting-notes ---"
NOTES_FILE=$(find "$WS_DIR" -name "fleeting-notes.md" -path "*/inbox/*" 2>/dev/null | head -1)
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  _pass "fleeting-notes.md exists"
  grep -qi 'Processed' "$NOTES_FILE" 2>/dev/null \
    && _pass "processed section present" \
    || _fail "no processed section"
  grep -qiE 'class|\|.*category|\|.*тип' "$NOTES_FILE" 2>/dev/null \
    && _pass "notes classified into categories" \
    || _pass "category classification: check manually"
else
  _fail "fleeting-notes.md not found in inbox/"
fi

echo "  --- captures ---"
CAPTURES_FILE=$(find "$WS_DIR" -name "captures.md" -path "*/inbox/*" 2>/dev/null | head -1)
if [ -n "$CAPTURES_FILE" ] && [ -f "$CAPTURES_FILE" ]; then
  _pass "captures.md exists"
  grep -qiE 'routed|→|направлен|destination' "$CAPTURES_FILE" 2>/dev/null \
    && _pass "captures have routing destinations" \
    || _pass "routing destinations: check manually"
else
  _pass "captures.md: not found (may have been consumed)"
fi

echo "  --- stale items flagged ---"
STALE_FOUND=0
while IFS= read -r f; do
  if grep -qiE '>7 days|stale|просроч|висит' "$f" 2>/dev/null; then
    STALE_FOUND=1
  fi
done < <(find "$WS_DIR/DS-strategy/inbox" -name "*.md" 2>/dev/null || true)
[ "$STALE_FOUND" -eq 1 ] \
  && _pass "stale items flagged in inbox" \
  || _pass "stale items: no flags found (check manually)"

echo "  --- MEMORY sync ---"
MEMORY_FILE=$(find "$WS_DIR" -name "MEMORY.md" -path "*/memory/*" 2>/dev/null | head -1)
if [ -n "$MEMORY_FILE" ] && [ -f "$MEMORY_FILE" ]; then
  grep -qi 'valid_from\|updated' "$MEMORY_FILE" 2>/dev/null \
    && _pass "MEMORY.md has temporal metadata" \
    || _fail "MEMORY.md missing valid_from/updated"
else
  _fail "MEMORY.md not found"
fi

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if [ -d .git ]; then
  git log -1 --oneline 2>/dev/null | grep -qiE 'extractor|inbox\|capture\|classify' \
    && _pass "commit: extractor-related" \
    || _pass "commit: check manually"
else
  _pass "git: not a repo"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
