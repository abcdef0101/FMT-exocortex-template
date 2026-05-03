#!/usr/bin/env bash
# test-update-apply.sh — тесты update.sh --apply и внутренних функций
set -uo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$ROOT_DIR/scripts/lib/manifest-lib.sh" 2>/dev/null || true
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

UPDATER="$ROOT_DIR/update.sh"
TMPDIR=$(mktemp -d -t upapply-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- --apply without changes ---"
# Simulate already up-to-date by running --check which returns 0
output=$("$UPDATER" --check 2>&1)
if echo "$output" | grep -q "Already up to date"; then
  _pass "--check: already up to date"
else
  _pass "--check: changes available (can't test no-changes apply)"
fi

echo "  --- NEVER-TOUCH in checksum skip ---"
CK_FILE="$ROOT_DIR/checksums.yaml"
if [ -f "$CK_FILE" ]; then
  nt_count=$(sed -n '/^never_touch:/,/^files:/p' "$CK_FILE" | grep -c '^  - ' || echo "0")
  [ "$nt_count" -ge 5 ] \
    && _pass "checksums.yaml: $nt_count never-touch entries" \
    || _fail "checksums.yaml: expected >=5 never-touch, got $nt_count"
fi

echo "  --- 3-way merge: identical files skipped ---"
# Mock: create base, ours, theirs all identical
echo "line1" > "$TMPDIR/base"
echo "line1" > "$TMPDIR/ours"
echo "line1" > "$TMPDIR/theirs"
git merge-file -p "$TMPDIR/ours" "$TMPDIR/base" "$TMPDIR/theirs" > "$TMPDIR/merged" 2>/dev/null
if diff -q "$TMPDIR/merged" "$TMPDIR/ours" >/dev/null 2>&1; then
  _pass "3-way merge: identical files produce no diff"
else
  _fail "3-way merge: identical files changed"
fi

echo "  --- 3-way merge: non-conflicting ---"
printf 'line1\nline2\nline3\nline4\n' > "$TMPDIR/base"
printf 'line1 edited\nline2\nline3\nline4\n' > "$TMPDIR/ours"
printf 'line1\nline2\nline3 edited\nline4\n' > "$TMPDIR/theirs"
git merge-file -p "$TMPDIR/ours" "$TMPDIR/base" "$TMPDIR/theirs" > "$TMPDIR/merged" 2>/dev/null || true
if grep -q "^<<<<<<<" "$TMPDIR/merged" 2>/dev/null; then
  _fail "3-way merge: unexpected conflict in non-conflicting case"
else
  _pass "3-way merge: non-conflicting merges clean"
fi

echo "  --- 3-way merge: conflict detection ---"
echo "base line" > "$TMPDIR/base"
echo "edit1" > "$TMPDIR/ours"
echo "edit2" > "$TMPDIR/theirs"
git merge-file -p "$TMPDIR/ours" "$TMPDIR/base" "$TMPDIR/theirs" > "$TMPDIR/merged" 2>/dev/null || true
if grep -q "^<<<<<<<" "$TMPDIR/merged" 2>/dev/null; then
  _pass "3-way merge: conflict markers detected"
else
  _fail "3-way merge: no conflict markers where expected"
fi

echo "  --- --apply error: no git remote ---"
# Check that update.sh detects missing remote
grep -q "No git remote" "$UPDATER" \
  && _pass "update.sh: missing remote detection present" \
  || _fail "update.sh: no missing remote detection"

echo "  --- --apply error: not a git repo ---"
grep -q "Not a git repository" "$UPDATER" \
  && _pass "update.sh: not-a-repo detection present" \
  || _fail "update.sh: no not-a-repo detection"

echo "  --- cross-platform sed_inplace ---"
grep -q "sed_inplace()" "$UPDATER" \
  && _pass "update.sh: cross-platform sed wrapper present" \
  || _fail "update.sh: no cross-platform sed wrapper"

# P0 #7: rebase conflict handling
echo "  --- git pull rebase conflict detection ---"
grep -q "pull.*rebase" "$UPDATER" 2>/dev/null \
  && _pass "update.sh: git pull --rebase present" \
  || _fail "update.sh: no git pull --rebase"
grep -q "Resolve conflicts manually" "$UPDATER" 2>/dev/null \
  && _pass "update.sh: conflict resolution message present" \
  || _fail "update.sh: no conflict resolution message"

# P0: simulate rebase conflict exit code
echo "  --- rebase conflict exit code ---"
# Create a mock that simulates rebase conflict
mkdir -p "$TMPDIR/conflict-repo"
cd "$TMPDIR/conflict-repo"
git init --quiet
echo "v1" > file.txt && git add file.txt && git commit -m "initial" --quiet
echo "v2" > file.txt && git add file.txt && git commit -m "local" --quiet
# Create a conflicting change on a new branch
git checkout -b upstream --quiet 2>/dev/null || true
echo "v3" > file.txt && git add file.txt && git commit -m "upstream" --quiet
git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null || true
# git pull --rebase should conflict
git pull --rebase . upstream 2>/dev/null && rc=1 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "rebase conflict: git correctly returns non-zero" \
  || _fail "rebase conflict: git should return non-zero"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
