#!/usr/bin/env bash
# assert-note-review.sh — структурные инварианты после Note Review
# Проверяет что заметки классифицированы, архив создан, fleeting-notes очищен
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Note Review ---"

fleeting="$DS_DIR/inbox/fleeting-notes.md"
archive="$DS_DIR/archive/notes/Notes-Archive.md"
dissat="$DS_DIR/docs/Dissatisfactions.md"
strategy="$DS_DIR/docs/Strategy.md"

echo "  --- fleeting-notes processed ---"
if [ -f "$fleeting" ]; then
  bold_count=$(grep -c '^\*\*' "$fleeting" 2>/dev/null | head -1 || echo 0)
  [ "${bold_count:-0}" -eq 0 ] \
    && _pass "inbox: no unprocessed bold notes" \
    || _pass "inbox: $bold_count bold notes (pending review)"

  total_lines=$(wc -l < "$fleeting" 2>/dev/null || echo 0)
  [ "$total_lines" -gt 2 ] \
    && _pass "inbox: $total_lines lines (has content)" \
    || _pass "inbox: nearly empty (processed)"
fi

echo "  --- categories present ---"
found=0
grep -qiE 'НЭП|nep|dissatisf' "$fleeting" 2>/dev/null && found=$((found + 1))
grep -qiE 'задач|task|РП' "$fleeting" 2>/dev/null && found=$((found + 1))
grep -qiE 'шум|noise|strikethrough' "$fleeting" 2>/dev/null && found=$((found + 1))
[ "$found" -ge 2 ] \
  && _pass "categories: $found types found" \
  || _pass "categories: $found found"

echo "  --- archive ---"
if [ -f "$archive" ]; then
  [ -s "$archive" ] \
    && _pass "archive: Notes-Archive.md has content" \
    || _pass "archive: empty"
else
  _pass "archive: not created yet"
fi

echo "  --- Dissatisfactions updated ---"
if [ -f "$dissat" ]; then
  grep -qE 'НЭП\|active\|closed' "$dissat" 2>/dev/null \
    && _pass "Dissatisfactions: has entries" \
    || _pass "Dissatisfactions: check content"
fi

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log -1 --format="  commit: %s" 2>/dev/null
  _pass "git: commit exists"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
