#!/usr/bin/env bash
# test-update-check.sh — тесты update.sh --check
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

UPDATER="$ROOT_DIR/update.sh"
TMPDIR=$(mktemp -d -t update-check-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

overlay_worktree_snapshot() {
  local dest="$1"
  (cd "$ROOT_DIR" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -)
}

commit_snapshot_if_dirty() {
  local repo="$1"
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet || [ -n "$(git -C "$repo" ls-files --others --exclude-standard)" ]; then
    git -C "$repo" add -A
    git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "test: sync worktree snapshot" --quiet
  fi
}

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
output=$("$UPDATER" --check 2>&1) && check_rc=0 || check_rc=$?
if [ "$check_rc" -eq 3 ]; then
  _pass "--check: graceful error exit (rc=3)"
elif [ "$check_rc" -eq 0 ]; then
  _pass "--check: clean exit (rc=0)"
else
  _fail "--check: unexpected exit code $check_rc"
fi
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

echo "  --- --check symlink validation ---"
WS_LINK="$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
if echo "$output" | grep -q "symlink valid"; then
  _pass "--check: symlink valid"
elif echo "$output" | grep -E -q "symlink.*(broken|missing)"; then
  _pass "--check: symlink check ran (needs fix)"
elif [ ! -L "$WS_LINK" ] && [ ! -d "$WS_LINK" ]; then
  _pass "--check: symlink validation skipped (no workspace)"
else
  _fail "--check: symlink validation missing despite active workspace"
  echo "    update.sh --check output:"
  echo "$output" | sed 's/^/    /'
fi

echo "  --- manifest-lib sourced ---"
grep -q "MANIFEST_LIB=.*manifest-lib" "$UPDATER" && grep -q 'source.*MANIFEST_LIB' "$UPDATER" \
  && _pass "update.sh sources manifest-lib.sh" \
  || _fail "update.sh does not source manifest-lib.sh"

# P1 #8: update.sh --check without checksums.yaml
echo "  --- --check without checksums.yaml ---"
git clone "$ROOT_DIR" "$TMPDIR/no-checksums" --quiet 2>/dev/null
overlay_worktree_snapshot "$TMPDIR/no-checksums"
commit_snapshot_if_dirty "$TMPDIR/no-checksums"
rm -f "$TMPDIR/no-checksums/checksums.yaml"
output=$(bash "$TMPDIR/no-checksums/update.sh" --check 2>&1) || true
echo "$output" | grep -q "checksums.yaml not found" 2>/dev/null \
  && _pass "update.sh: graceful skip when checksums.yaml missing" \
  || _fail "update.sh: no warning when checksums.yaml missing"

# P1 #9: update.sh without workspace → graceful skip
echo "  --- --check without workspace ---"
grep -q "WORKSPACE_FULL_PATH" "$UPDATER" 2>/dev/null \
  && _pass "update.sh: workspace-aware (WORKSPACE_FULL_PATH used)" \
  || _fail "update.sh: no workspace handling"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
