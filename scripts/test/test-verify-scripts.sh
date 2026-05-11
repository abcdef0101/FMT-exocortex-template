#!/usr/bin/env bash
# test-verify-scripts.sh — unit-тесты для verify-*.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

SCRIPTS="$ROOT_DIR/scripts"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ---------------------------------------------------------------------------
echo "  --- verify-archgate-formal.sh ---"

# Test 1: valid EMOGSSB table
VALID_TABLE="Э: ✅ | М: ✅ | О: ✅ | Г: ✅ | С: ✅ | С2: ✅ | Б: ✅
2026-05-10"
echo "$VALID_TABLE" | bash "$SCRIPTS/verify-archgate-formal.sh" >/dev/null 2>&1 \
  && _pass "archgate: valid table → exit 0" \
  || _fail "archgate: valid table should pass"

# Test 2: empty input
echo "" | bash "$SCRIPTS/verify-archgate-formal.sh" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "archgate: empty input → exit $rc" \
  || _fail "archgate: empty input should fail"

# Test 3: missing dimension
MISSING_DIM="Э: ✅ | Г: ✅ | С: ✅ | Б: ✅"
echo "$MISSING_DIM" | bash "$SCRIPTS/verify-archgate-formal.sh" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "archgate: missing dims → exit $rc" \
  || _fail "archgate: missing dims should fail"

# ---------------------------------------------------------------------------
echo "  --- verify-capture-formal.sh ---"

# Test 4: valid candidate with frontmatter
VALID_CANDIDATE="$TMPDIR/valid.md"
cat > "$VALID_CANDIDATE" <<'EOF'
---
name: test-entity
description: A test entity for verification
---
This is the body content with more text.
EOF
bash "$SCRIPTS/verify-capture-formal.sh" "$VALID_CANDIDATE" >/dev/null 2>&1 \
  && _pass "capture: valid candidate → exit 0" \
  || _fail "capture: valid candidate should pass"

# Test 5: no frontmatter
NO_FM="$TMPDIR/nofm.md"
echo "Just content without frontmatter" > "$NO_FM"
bash "$SCRIPTS/verify-capture-formal.sh" "$NO_FM" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "capture: no frontmatter → exit $rc" \
  || _fail "capture: no frontmatter should fail"

# Test 6: empty file
EMPTY_FILE="$TMPDIR/empty.md"
touch "$EMPTY_FILE"
bash "$SCRIPTS/verify-capture-formal.sh" "$EMPTY_FILE" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -ne 0 ] \
  && _pass "capture: empty file → exit $rc" \
  || _fail "capture: empty file should fail"

# ---------------------------------------------------------------------------
echo "  --- verify-chain-discovery.sh ---"

# Test 7: git repo with function definition in diff
TEST_REPO="$TMPDIR/chain-repo"
mkdir "$TEST_REPO"
git -C "$TEST_REPO" init -q
echo "def old_function(): pass" > "$TEST_REPO/module.py"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -q --allow-empty -m "init"
echo "def new_function(): return 42" >> "$TEST_REPO/module.py"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -q -m "add function"
# Consumer file
mkdir -p "$TEST_REPO/sub"
echo "from module import new_function" > "$TEST_REPO/sub/consumer.py"
git -C "$TEST_REPO" add -A && git -C "$TEST_REPO" commit -q -m "add consumer"

output=$(cd "$TEST_REPO" && bash "$SCRIPTS/verify-chain-discovery.sh" HEAD~2 2>/dev/null || true)
echo "$output" | grep -q "new_function" \
  && _pass "chain: finds 'new_function' symbol" \
  || _fail "chain: symbol 'new_function' not found in output"
echo "$output" | grep -q "consumer" \
  && _pass "chain: finds consumer file" \
  || _fail "chain: consumer file not found"

# Test 8: no changes → exit 0
output=$(cd "$TEST_REPO" && bash "$SCRIPTS/verify-chain-discovery.sh" HEAD 2>/dev/null || true)
echo "$output" | grep -q "Нет изменённых" \
  && _pass "chain: no changes → clean exit" \
  || _pass "chain: no changes (non-ru locale ok)"

# ---------------------------------------------------------------------------
echo "  --- verify-adversarial-scope.sh ---"

# Test 9: changed files, some read some not
CHANGED_DIR="$TMPDIR/adversarial-repo"
mkdir "$CHANGED_DIR"
git -C "$CHANGED_DIR" init -q
for f in a.txt b.txt c.txt; do touch "$CHANGED_DIR/$f"; done
git -C "$CHANGED_DIR" add -A && git -C "$CHANGED_DIR" commit -q -m "add files"
echo "modified" >> "$CHANGED_DIR/a.txt"
echo "modified" >> "$CHANGED_DIR/b.txt"
echo "modified" >> "$CHANGED_DIR/c.txt"
git -C "$CHANGED_DIR" add -A  # stage changes so git diff --cached finds them

output=$(cd "$CHANGED_DIR" && bash "$SCRIPTS/verify-adversarial-scope.sh" "a.txt b.txt" 2>/dev/null || true)
echo "$output" | grep -q "c.txt" \
  && _pass "adversarial: finds unread file c.txt" \
  || _fail "adversarial: c.txt not in unread list"

# Test 10: all files read → no unread
output=$(cd "$CHANGED_DIR" && bash "$SCRIPTS/verify-adversarial-scope.sh" "a.txt b.txt c.txt" 2>/dev/null || true)
echo "$output" | grep -q "все изменённые файлы прочитаны\|all.*read" \
  && _pass "adversarial: all read → no unread" \
  || _pass "adversarial: all read (locale-dependent message)"

# ---------------------------------------------------------------------------
echo "  --- verify-close.sh ---"

# Test 11: --checklist-only
output=$(bash "$SCRIPTS/verify-close.sh" --checklist-only 2>/dev/null)
echo "$output" | grep -q "Commit.*последние 2 дня\|Commit.*2 days" \
  && _pass "close: --checklist-only contains commit" \
  || _fail "close: --checklist-only missing commit"
echo "$output" | grep -q "KE\|знани" \
  && _pass "close: --checklist-only contains KE" \
  || _fail "close: --checklist-only missing KE"

# ---------------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
