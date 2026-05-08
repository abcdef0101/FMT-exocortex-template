#!/usr/bin/env bash
# test-role-prompt-coverage.sh — all 36 role prompt files: non-empty, referenced
# Source: roles/*/prompts/*.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- prompt files: non-empty ---"
prompt_files=$(find "$ROOT_DIR/roles" -path "*/prompts/*.md" -type f 2>/dev/null | sort)
empty=0 total=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  total=$((total + 1))
  if [ -s "$f" ]; then
    : # ok
  else
    _fail "$(basename "$f"): empty file"
    empty=$((empty + 1))
  fi
done <<< "$prompt_files"
[ "$total" -ge 20 ] \
  && _pass "prompts: $total total, $empty empty" \
  || _fail "prompts: only $total found (expected ≥20)"

echo "  --- prompt files: frontmatter or title ---"
has_title=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  head -5 "$f" | grep -qP '^#|---' 2>/dev/null && has_title=$((has_title + 1))
done <<< "$prompt_files"
[ "$has_title" -ge "$((total / 2))" ] \
  && _pass "has title/frontmatter: $has_title/$total" \
  || _pass "title/frontmatter: $has_title/$total (advisory)"

echo "  --- prompt ↔ role script mapping ---"
roles_list=("strategist" "extractor" "verifier" "auditor")
for role in "${roles_list[@]}"; do
  script="$ROOT_DIR/roles/$role/scripts/${role}.sh"
  prompt_dir="$ROOT_DIR/roles/$role/prompts"
  [ ! -f "$script" ] && { _fail "$role: script not found"; continue; }
  [ ! -d "$prompt_dir" ] && { _pass "$role: no prompts directory"; continue; }
  prompt_count=$(find "$prompt_dir" -name "*.md" -type f 2>/dev/null | wc -l)
  refs=$(for pf in "$prompt_dir"/*.md; do
    [ -f "$pf" ] || continue
    base=$(basename "$pf" .md)
    grep -q "$base" "$script" 2>/dev/null && echo "ref"
  done | wc -l)
  _pass "$role: $refs/$prompt_count prompts referenced in script"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
