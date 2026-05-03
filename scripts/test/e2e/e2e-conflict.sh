#!/usr/bin/env bash
# E2E-7: 3-way merge — non-conflicting changes merge clean
# E2E-8: 3-way merge — conflict detection
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== E2E-7: 3-way merge — non-conflicting ==="

TMPDIR=$(mktemp -d -t e2e-conflict-XXXXXX)
trap 'rm -rf "$TMPDIR" 2>/dev/null; e2e_cleanup' EXIT

# Create base file (simulating common ancestor)
printf 'line1\nline2\nline3\nline4\nline5\n' > "$TMPDIR/base"

# Ours: modify line 1
printf 'line1-ours\nline2\nline3\nline4\nline5\n' > "$TMPDIR/ours"

# Theirs: modify line 3 (different location)
printf 'line1\nline2\nline3-theirs\nline4\nline5\n' > "$TMPDIR/theirs"

git merge-file -p "$TMPDIR/ours" "$TMPDIR/base" "$TMPDIR/theirs" > "$TMPDIR/merged" 2>/dev/null || true

if grep -q "^<<<<<<<" "$TMPDIR/merged" 2>/dev/null; then
  e2e_fail "non-conflicting merge: unexpected conflict"
else
  grep -q "line1-ours" "$TMPDIR/merged" \
    && e2e_pass "non-conflicting merge: ours change preserved" \
    || e2e_fail "non-conflicting merge: ours change lost"
  grep -q "line3-theirs" "$TMPDIR/merged" \
    && e2e_pass "non-conflicting merge: theirs change preserved" \
    || e2e_fail "non-conflicting merge: theirs change lost"
fi

# === E2E-8 ===
echo ""
echo "=== E2E-8: 3-way merge — conflict detection ==="

printf 'line1\nline2\n' > "$TMPDIR/base2"
printf 'ours-edit\nline2\n' > "$TMPDIR/ours2"
printf 'theirs-edit\nline2\n' > "$TMPDIR/theirs2"

git merge-file -p "$TMPDIR/ours2" "$TMPDIR/base2" "$TMPDIR/theirs2" > "$TMPDIR/merged2" 2>/dev/null || true

if grep -q "^<<<<<<<" "$TMPDIR/merged2" 2>/dev/null; then
  e2e_pass "conflict: markers detected in output"
  # Verify conflict markers structure
  grep -q "^<<<<<<<" "$TMPDIR/merged2" && e2e_pass "conflict: <<<<<<< marker present"
  grep -q "^=======" "$TMPDIR/merged2" && e2e_pass "conflict: ======= marker present"
  grep -q "^>>>>>>>" "$TMPDIR/merged2" && e2e_pass "conflict: >>>>>>> marker present"
else
  e2e_fail "conflict: no markers where expected"
fi

# Verify update.sh has conflict resolution message
grep -q "CONFLICT\|Resolve conflicts" "$ROOT_DIR/update.sh" 2>/dev/null \
  && e2e_pass "update.sh: conflict handling code present" \
  || e2e_fail "update.sh: no conflict handling"

rm -rf "$TMPDIR"

e2e_done
