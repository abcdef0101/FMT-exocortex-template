#!/usr/bin/env bash
# test-e2e-lib.sh — тесты для e2e/_lib.sh (P2-QUAL-02)
# Проверяет функции общей библиотеки E2E в изоляции
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

LIB="$ROOT_DIR/scripts/test/e2e/_lib.sh"

echo "  --- syntax + source ---"
bash -n "$LIB" 2>/dev/null \
  && _pass "_lib.sh syntax ok" \
  || _fail "_lib.sh syntax error"

source "$LIB" 2>/dev/null \
  && _pass "_lib.sh sources without error" \
  || { _fail "_lib.sh source failed"; exit 1; }

echo "  --- assertion helpers ---"

E2E_PASS=0 E2E_FAIL=0
e2e_pass "test pass 1"
[ "$E2E_PASS" -eq 1 ] && _pass "e2e_pass increments E2E_PASS" || _fail "E2E_PASS=$E2E_PASS"
e2e_fail "test fail 1"
[ "$E2E_FAIL" -eq 1 ] && _pass "e2e_fail increments E2E_FAIL" || _fail "E2E_FAIL=$E2E_FAIL"

e2e_done >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "e2e_done returns FAIL count (1)" \
  || _fail "e2e_done returned $rc"

E2E_PASS=0 E2E_FAIL=0
e2e_done >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 0 ] \
  && _pass "e2e_done returns 0 when no failures" \
  || _fail "e2e_done returned $rc"

echo "  --- repo operations ---"

TMPDIR=$(mktemp -d -t e2e-lib-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# setup_upstream
setup_upstream >/dev/null 2>&1 && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ -d "${UPSTREAM_DIR:-}" ]; then
  _pass "setup_upstream creates clone"
  [ -d "$UPSTREAM_DIR/.git" ] && _pass "setup_upstream: .git exists" || _fail "setup_upstream: no .git"
else
  _fail "setup_upstream failed (rc=$rc)"
fi

# setup_local
setup_local >/dev/null 2>&1 && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ -d "${LOCAL_DIR:-}" ]; then
  _pass "setup_local creates local clone"
else
  _fail "setup_local failed (rc=$rc)"
fi

# inject_change
if [ -n "${LOCAL_DIR:-}" ] && [ -d "$LOCAL_DIR" ]; then
  inject_change "$LOCAL_DIR" "test-change.txt" "e2e-lib test content"
  [ -f "$LOCAL_DIR/test-change.txt" ] \
    && _pass "inject_change: file created" \
    || _fail "inject_change: file not found"
  grep -q "e2e-lib test content" "$LOCAL_DIR/test-change.txt" 2>/dev/null \
    && _pass "inject_change: content present" \
    || _fail "inject_change: content missing"
  git -C "$LOCAL_DIR" log -1 --format=%s 2>/dev/null | grep -q '^e2e: inject change$' \
    && _pass "inject_change: commit created" \
    || _fail "inject_change: commit missing"
  git -C "$LOCAL_DIR" rev-parse main >/dev/null 2>&1 \
    && _pass "inject_change: main ref updated" \
    || _fail "inject_change: main ref missing"
else
  _pass "inject_change: skipped (no local clone)"
fi

echo "  --- workspace operations ---"

setup_workspace "$TMPDIR" >/dev/null 2>&1
[ -d "${WS_DIR:-}" ] \
  && _pass "setup_workspace creates directory" \
  || _fail "setup_workspace: WS_DIR=$WS_DIR"
[ "${WORKSPACE_FULL_PATH:-}" = "$WS_DIR" ] \
  && _pass "setup_workspace exports WORKSPACE_FULL_PATH" \
  || _fail "setup_workspace: WORKSPACE_FULL_PATH=${WORKSPACE_FULL_PATH:-} != $WS_DIR"

echo "  --- verification helpers ---"

# verify_workspace_structure needs a valid workspace — use a minimal mock
MOCK_WS="$TMPDIR/mock-ws"
mkdir -p "$MOCK_WS/memory"
mkdir -p "$MOCK_WS/.claude"
mkdir -p "$MOCK_WS/extensions/mcps"
touch "$MOCK_WS/CLAUDE.md"
touch "$MOCK_WS/params.yaml"
touch "$MOCK_WS/memory/MEMORY.md"
touch "$MOCK_WS/memory/day-rhythm-config.yaml"
touch "$MOCK_WS/.claude/settings.local.json"
touch "$MOCK_WS/.mcp.json"
ln -sfn "../../../persistent-memory/" "$MOCK_WS/memory/persistent-memory" 2>/dev/null || true

E2E_PASS=0 E2E_FAIL=0
verify_workspace_structure "$MOCK_WS" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 0 ] \
  && _pass "verify_workspace_structure: all files present" \
  || _fail "verify_workspace_structure: $rc errors"

# verify_symlink
E2E_PASS=0 E2E_FAIL=0
verify_symlink "$MOCK_WS" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" -eq 0 ] \
  && _pass "verify_symlink: detects symlink" \
  || _fail "verify_symlink: failed"

# verify_never_touch
E2E_PASS=0 E2E_FAIL=0
echo "preserved content" > "$TMPDIR/never-touch-test.txt"
verify_never_touch "$TMPDIR/never-touch-test.txt" "preserved content" >/dev/null 2>&1
[ "$E2E_FAIL" -eq 0 ] && _pass "verify_never_touch: matches pattern" || _fail "verify_never_touch: failed"

# verify_checksums
E2E_PASS=0 E2E_FAIL=0
CK_FILE="$TMPDIR/mock-checksums.yaml"
for i in $(seq 1 150); do echo "  file_$i: sha256"; done > "$CK_FILE"
verify_checksums "$CK_FILE" >/dev/null 2>&1
[ "$E2E_FAIL" -eq 0 ] && _pass "verify_checksums: >100 entries" || _fail "verify_checksums: failed"

echo "  --- cleanup ---"

e2e_cleanup >/dev/null 2>&1
[ ! -d "${UPSTREAM_DIR:-/nonexistent}" ] && [ ! -d "${LOCAL_DIR:-/nonexistent}" ] \
  && _pass "e2e_cleanup: removes temp dirs" \
  || _fail "e2e_cleanup: dirs still exist"

# trap is set by _lib.sh at source time — test script's own trap overrides it, which is expected

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
