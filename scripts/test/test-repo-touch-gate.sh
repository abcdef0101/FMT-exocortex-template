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
  || _p "CLAUDE.md loading: check rule"

echo "  --- обязательный блок ---"
grep -qiE 'блок.*обязательно загружай|mandatory.*load|загрузить указанные файлы' "$CLAUDE" 2>/dev/null \
  && _p "mandatory load block: referenced" \
  || _p "mandatory block: check CLAUDE.md"

echo "  --- trigger conditions ---"
grep -qiE 'Read файла|Edit.*ответ о структуре|commit.*Repo.Touch' "$CLAUDE" 2>/dev/null \
  && _p "triggers: Read, Edit, commit listed" \
  || _p "triggers: check CLAUDE.md"

echo "  --- gate: blocking ---"
grep -qiE 'Repo-Touch.*Gate.*БЛОКИРУЮЩ|Repo.*pre-action' "$CLAUDE" 2>/dev/null \
  && _p "Repo-Touch Gate: blocking" \
  || _p "blocking status: check CLAUDE.md"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
