#!/usr/bin/env bash
# test-update-check.sh — тесты update.sh --check
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

UPDATER="$ROOT_DIR/update.sh"

echo "  --- syntax check ---"
bash -n "$UPDATER" 2>/dev/null \
  && _pass "update.sh bash syntax ok" \
  || _fail "update.sh syntax error"

echo "  --- --version ---"
output=$("$UPDATER" --version 2>&1)
echo "$output" | grep -q "exocortex-update v" \
  && _pass "--version shows version" \
  || _fail "--version shows version"

echo "  --- --help ---"
output=$("$UPDATER" --help 2>&1)
echo "$output" | grep -q "\-\-check" \
  && _pass "--help shows --check" \
  || _fail "--help shows --check"
echo "$output" | grep -q "\-\-apply" \
  && _pass "--help shows --apply" \
  || _fail "--help shows --apply"

echo "  --- no args ---"
"$UPDATER" 2>&1 >/dev/null && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "no args exits 1" \
  || _fail "no args exits $rc (expected 1)"

echo "  --- unknown arg ---"
"$UPDATER" --unknown 2>&1 >/dev/null && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "unknown arg exits 1" \
  || _fail "unknown arg exits $rc (expected 1)"

echo "  --- --check output sections ---"
output=$("$UPDATER" --check 2>&1)
echo "$output" | grep -q "Fetching upstream" \
  && _pass "--check: fetch section" || _fail "--check: fetch section"
echo "$output" | grep -q "Comparing component versions" \
  && _pass "--check: version section" || _fail "--check: version section"
echo "$output" | grep -q "Verifying checksums" \
  && _pass "--check: checksum section" || _fail "--check: checksum section"
echo "$output" | grep -q "extension compatibility" \
  && _pass "--check: compat section" || _fail "--check: compat section"
echo "$output" | grep -q "Post-update" \
  && _pass "--check: post-update section" || _fail "--check: post-update section"

echo "  --- --check exit code ---"
"$UPDATER" --check >/dev/null 2>&1 && rc=0 || rc=$?
# Exit 0 = up to date, Exit 1 = changes available — both OK
[ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] \
  && _pass "--check exit code $rc (0=up-to-date, 1=changes, both valid)" \
  || _fail "--check exit code $rc (expected 0 or 1)"

echo "  --- --check symlink validation ---"
output=$("$UPDATER" --check 2>&1)
if echo "$output" | grep -q "symlink valid"; then
  _pass "--check: symlink validation present"
elif echo "$output" | grep -q "symlink.*broken\|symlink.*missing"; then
  _pass "--check: symlink validation present (needs fix)"
else
  _fail "--check: no symlink validation"
fi

echo "  --- manifest-lib sourced ---"
grep -q "MANIFEST_LIB=.*manifest-lib" "$UPDATER" && grep -q 'source.*MANIFEST_LIB' "$UPDATER" \
  && _pass "update.sh sources manifest-lib.sh" \
  || _fail "update.sh does not source manifest-lib.sh"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
