#!/usr/bin/env bash
# test-repo-touch-gate.sh — Repo-Touch Gate: CLAUDE.md загрузка при первом действии
# Source: CLAUDE.md §2 (Pre-action Gates)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_p() { echo "  ✓ $1"; }
_f() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- Repo-Touch Gate in CLAUDE.md ---"
grep -qiE 'Repo-Touch Gate|Repo.Touch.*Gate|первое.*действие.*репо' "$CLAUDE" 2>/dev/null \
  && _p "Repo-Touch Gate: rule present" \
  || _f "Repo-Touch Gate rule not found"

echo "  --- CLAUDE.md loading requirement ---"
grep -qiE 'прочитать.*CLAUDE.md|read.*CLAUDE.md|загрузить.*CLAUDE' "$CLAUDE" 2>/dev/null \
  && _p "CLAUDE.md loading: required" \
  || _f "CLAUDE.md loading: requirement not found"

echo "  --- обязательный блок ---"
grep -qiE 'блок.*обязательно загружай|mandatory.*load|загрузить указанные файлы' "$CLAUDE" 2>/dev/null \
  && _p "mandatory load block: referenced" \
  || _f "mandatory load block: not found"

echo "  --- trigger conditions ---"
grep -qiE 'Read файла|Edit.*ответ о структуре|commit.*Repo.Touch' "$CLAUDE" 2>/dev/null \
  && _p "triggers: Read, Edit, commit listed" \
  || _f "trigger conditions: not found"

echo "  --- gate: blocking ---"
{ grep -q 'Repo-Touch Gate' "$CLAUDE" && grep -q 'Pre-action Gates' "$CLAUDE"; } \
  && _p "Repo-Touch Gate: defined under Pre-action Gates" \
  || _f "Repo-Touch Gate: not linked to Pre-action Gates section"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
