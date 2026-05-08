#!/usr/bin/env bash
# test-memory-metadata.sh — temporal metadata check (§2, workflow-full.md)
# Каждый файл в persistent-memory/ должен иметь valid_from в frontmatter
# Устаревшие — superseded_by
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PM_DIR="$ROOT_DIR/persistent-memory"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

echo "  --- valid_from check (all persistent-memory/*.md, advisory) ---"

missing_vf=0
while IFS= read -r -d '' f; do
  name=$(basename "$f")
  if grep -q '^valid_from:' "$f" 2>/dev/null; then
    vf=$(grep '^valid_from:' "$f" | head -1 | sed 's/^valid_from: *//')
    _pass "$name: valid_from=$vf"
  else
    _warn "$name: missing valid_from (advisory — add gradually)"
    missing_vf=$((missing_vf + 1))
  fi
done < <(find "$PM_DIR" -maxdepth 1 -name "*.md" -type f ! -name "MANIFEST.yaml" -print0)

echo "  --- superseded_by check ---"

while IFS= read -r -d '' f; do
  name=$(basename "$f")
  if grep -q '^superseded_by:' "$f" 2>/dev/null; then
    sb=$(grep '^superseded_by:' "$f" | head -1 | sed 's/^superseded_by: *//')
    _pass "$name: superseded_by=$sb"
  fi
done < <(find "$PM_DIR" -maxdepth 1 -name "*.md" -type f ! -name "MANIFEST.yaml" -print0)

echo "  --- MEMORY.md valid_from ---"
WS_DIR="${WORKSPACE_DIR:-$ROOT_DIR/workspaces/CURRENT_WORKSPACE}"
if [ -L "$WS_DIR" ]; then WS_DIR=$(cd "$WS_DIR" && pwd -P 2>/dev/null || echo "$WS_DIR"); fi
MEMORY_MD="$WS_DIR/memory/MEMORY.md"
if [ -f "$MEMORY_MD" ]; then
  grep -q 'valid_from' "$MEMORY_MD" 2>/dev/null \
    && _pass "MEMORY.md: valid_from present" \
    ||   _warn "MEMORY.md: missing valid_from (advisory)"
fi

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL file(s) missing metadata"
exit $FAIL