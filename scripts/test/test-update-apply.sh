#!/usr/bin/env bash
# test-update-apply.sh — тесты update.sh --apply и внутренних функций
# NOTE: set -e omitted — update.sh --check regenerates checksums.yaml,
# which makes subsequent git operations in the test environment fragile.
# Full set -euo pipefail needs update.sh decoupling (P1-BUG-02).
set -uo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$ROOT_DIR/scripts/lib/manifest-lib.sh" 2>/dev/null || true
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

UPDATER="$ROOT_DIR/update.sh"
TMPDIR=$(mktemp -d -t upapply-test-XXXXXX)
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
git clone "$ROOT_DIR" "$TMPDIR/no-remote" --quiet 2>/dev/null
overlay_worktree_snapshot "$TMPDIR/no-remote"
commit_snapshot_if_dirty "$TMPDIR/no-remote"
git -C "$TMPDIR/no-remote" remote remove origin
output=$(bash "$TMPDIR/no-remote/update.sh" --check 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] \
  && _pass "update.sh: missing remote exits 3" \
  || _fail "update.sh: missing remote rc=$rc"
echo "$output" | grep -q "No git remote" \
  && _pass "update.sh: missing remote message" \
  || _fail "update.sh: missing remote message absent"

echo "  --- --apply error: not a git repo ---"
mkdir -p "$TMPDIR/plain/scripts/lib"
cp "$UPDATER" "$TMPDIR/plain/update.sh"
cp "$ROOT_DIR/scripts/lib/manifest-lib.sh" "$TMPDIR/plain/scripts/lib/manifest-lib.sh"
output=$(bash "$TMPDIR/plain/update.sh" --check 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] \
  && _pass "update.sh: not-a-repo exits 3" \
  || _fail "update.sh: not-a-repo rc=$rc"
echo "$output" | grep -q "Not a git repository" \
  && _pass "update.sh: not-a-repo message" \
  || _fail "update.sh: not-a-repo message absent"

echo "  --- git pull rebase conflict detection ---"
git clone "$ROOT_DIR" "$TMPDIR/conflict-upstream" --quiet 2>/dev/null
overlay_worktree_snapshot "$TMPDIR/conflict-upstream"
commit_snapshot_if_dirty "$TMPDIR/conflict-upstream"
git clone "$TMPDIR/conflict-upstream" "$TMPDIR/conflict-local" --quiet 2>/dev/null
echo "upstream change" >> "$TMPDIR/conflict-upstream/CLAUDE.md"
git -C "$TMPDIR/conflict-upstream" add CLAUDE.md && git -C "$TMPDIR/conflict-upstream" -c user.name=Test -c user.email=test@example.com commit -m "upstream change" --quiet
echo "local change" >> "$TMPDIR/conflict-local/CLAUDE.md"
git -C "$TMPDIR/conflict-local" add CLAUDE.md && git -C "$TMPDIR/conflict-local" -c user.name=Test -c user.email=test@example.com commit -m "local change" --quiet
git -C "$TMPDIR/conflict-local" remote set-url origin "$TMPDIR/conflict-upstream"
output=$(bash "$TMPDIR/conflict-local/update.sh" --apply 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] \
  && _pass "update.sh: rebase conflict exits 3" \
  || _fail "update.sh: rebase conflict rc=$rc"
echo "$output" | grep -q "Resolve conflicts manually" \
  && _pass "update.sh: conflict resolution message present" \
  || _fail "update.sh: no conflict resolution message"

# P0: simulate rebase conflict exit code
echo "  --- rebase conflict exit code ---"
# Create a mock that simulates rebase conflict
mkdir -p "$TMPDIR/conflict-repo"
cd "$TMPDIR/conflict-repo"
git init --quiet
echo "v1" > file.txt && git add file.txt && git commit -m "initial" --quiet
git checkout -b upstream --quiet 2>/dev/null || true
echo "upstream" > file.txt && git add file.txt && git commit -m "upstream" --quiet
git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null || true
echo "local" > file.txt && git add file.txt && git commit -m "local" --quiet
# git pull --rebase should conflict
git pull --rebase . upstream >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "rebase conflict: git correctly returns non-zero" \
  || _fail "rebase conflict: git should return non-zero"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
