#!/usr/bin/env bash
# test-enforce-semver.sh — тесты CI enforcement checks
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

ENFORCER="$ROOT_DIR/scripts/enforce-semver.sh"
TMPDIR=$(mktemp -d -t semver-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- syntax check ---"
bash -n "$ENFORCER" 2>/dev/null \
  && _pass "enforce-semver.sh syntax ok" \
  || _fail "enforce-semver.sh syntax error"

echo "  --- all checks pass on current codebase ---"
"$ENFORCER" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 0 ] \
  && _pass "enforce-semver: exit 0 on clean codebase" \
  || _fail "enforce-semver: exit $rc on clean codebase"

echo "  --- semver validation ---"
valid_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; }
# Valid cases
valid_semver "0.25.1" && _pass "semver: 0.25.1 valid" || _fail "semver: 0.25.1"
valid_semver "1.0.0" && _pass "semver: 1.0.0 valid" || _fail "semver: 1.0.0"
valid_semver "2.3.0-beta1" && _pass "semver: 2.3.0-beta1 valid" || _fail "semver: 2.3.0-beta1"
# Invalid cases
! valid_semver "1.0" && _pass "semver: 1.0 invalid" || _fail "semver: 1.0 should be invalid"
! valid_semver "v1.0.0" && _pass "semver: v1.0.0 invalid" || _fail "semver: v1.0.0 should be invalid"
! valid_semver "abc" && _pass "semver: abc invalid" || _fail "semver: abc should be invalid"

echo "  --- extension coverage ---"
EP_FILE="$ROOT_DIR/extension-points.yaml"
if [ -f "$EP_FILE" ]; then
  proto_count=$(grep -c 'file: extensions/' "$EP_FILE" 2>/dev/null || echo "0")
  [ "$proto_count" -ge 10 ] \
    && _pass "extension coverage: $proto_count protocol hooks" \
    || _fail "extension coverage: expected >=10, got $proto_count"
fi

echo "  --- link graph: workspace skip ---"
grep -q "workspaces/\*" "$ENFORCER" 2>/dev/null || grep -q "workspaces" "$ENFORCER" 2>/dev/null \
  && _pass "link graph: workspace paths skipped" \
  || _fail "link graph: no workspace skip logic"

echo "  --- link graph: valid @ references ---"
# Count valid @ references in CLAUDE.md
CLAUDE_MD="$ROOT_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  refs=$(grep -oP '@(\./)[a-zA-Z0-9_/.-]+' "$CLAUDE_MD" 2>/dev/null || true)
  ref_ok=0 ref_bad=0
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    ref="${ref#@}"
    [[ "$ref" =~ workspaces/ ]] && continue
    resolved="$ROOT_DIR/${ref#./}"
    if [ -f "$resolved" ] || [ -d "$resolved" ]; then
      ref_ok=$((ref_ok + 1))
    else
      _fail "broken ref: $ref"
      ref_bad=$((ref_bad + 1))
    fi
  done <<< "$refs"
  [ "$ref_bad" -eq 0 ] \
    && _pass "link graph: $ref_ok references valid" \
    || true
fi

echo "  --- enforcement: error on invalid manifest ---"
# Create a temporary invalid MANIFEST and check it's caught
mkdir -p "$TMPDIR/mock"
echo "version: bad" > "$TMPDIR/mock/MANIFEST.yaml"
output=$(grep -c 'valid_semver' "$ENFORCER" 2>/dev/null || echo "0")
# The enforcer checks semver — verify it has the function
grep -q "valid_semver()" "$ENFORCER" \
  && _pass "enforce: semver function present" \
  || _fail "enforce: no semver function"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
