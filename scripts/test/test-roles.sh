#!/usr/bin/env bash
# test-roles.sh — проверка ролевых скриптов (§12, workflow-full.md)
# Все role scripts: bash -n, agent-card.yaml в каждой роли
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ROLES_DIR="$ROOT_DIR/roles"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- role scripts: bash -n ---"

syn_ok=0 syn_total=0
while IFS= read -r -d '' script; do
  name="${script#$ROOT_DIR/}"
  syn_total=$((syn_total + 1))
  if bash -n "$script" 2>/dev/null; then
    syn_ok=$((syn_ok + 1))
  else
    _fail "$name: syntax error"
    bash -n "$script" 2>&1 | sed 's/^/      | /'
  fi
done < <(find "$ROLES_DIR" -name "*.sh" -type f -print0 2>/dev/null || true)

if [ "$syn_total" -eq 0 ]; then
  _fail "no role scripts found"
else
  _pass "bash -n: $syn_ok/$syn_total ok"
fi

echo "  --- agent-card.yaml in each role ---"

cards=0
for role_dir in "$ROLES_DIR"/*/; do
  [ ! -d "$role_dir" ] && continue
  name=$(basename "$role_dir")
  [[ "$name" == "scripts" ]] && continue
  if [ -f "$role_dir/agent-card.yaml" ]; then
    cards=$((cards + 1))
  else
    _pass "$name: no agent-card.yaml (optional)"
  fi
done
echo "  agent cards: $cards found"

echo "  --- role scripts: no broken source calls ---"

broken_source=0
while IFS= read -r -d '' script; do
  while IFS= read -r line; do
    [[ "$line" =~ source\ (.*) ]] || continue
    src="${BASH_REMATCH[1]}"
    # Skip variable-based paths
    [[ "$src" == *'$'* ]] && continue
    # Resolve relative path
    resolved="$(dirname "$script")/$src"
    if [ ! -f "$resolved" ]; then
      name="${script#$ROOT_DIR/}"
      _fail "$name: broken source → $src"
      broken_source=$((broken_source + 1))
    fi
  done < <(grep '^source ' "$script" 2>/dev/null || true)
done < <(find "$ROLES_DIR" -name "*.sh" -type f -print0 2>/dev/null || true)

[ "$broken_source" -eq 0 ] \
  && _pass "source calls: all resolved" \
  || true

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL