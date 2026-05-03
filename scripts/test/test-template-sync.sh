#!/usr/bin/env bash
# test-template-sync.sh — тесты template-sync.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

SYNCER="$ROOT_DIR/template-sync.sh"
TMPDIR=$(mktemp -d -t tmplsync-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- syntax check ---"
bash -n "$SYNCER" 2>/dev/null \
  && _pass "template-sync.sh bash syntax ok" \
  || _fail "template-sync.sh syntax error"

echo "  --- no args ---"
"$SYNCER" 2>&1 >/dev/null && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "no args exits 1" \
  || _fail "no args exits $rc (expected 1)"

echo "  --- --version ---"
output=$("$SYNCER" --version 2>&1)
echo "$output" | grep -q "template-sync v" \
  && _pass "--version shows version" \
  || _fail "--version shows version"

echo "  --- --help ---"
output=$("$SYNCER" --help 2>&1)
echo "$output" | grep -q "\-\-check" \
  && _pass "--help shows --check" \
  || _fail "--help shows --check"
echo "$output" | grep -q "\-\-sync" \
  && _pass "--help shows --sync" \
  || _fail "--help shows --sync"

echo "  --- --check without author_mode ---"
# Create a mock params.yaml without author_mode
mkdir -p "$TMPDIR/mock"
echo "author_mode: false" > "$TMPDIR/mock/params.yaml"
# Test that the script checks author_mode
grep -q "author_mode" "$SYNCER" \
  && _pass "template-sync: author_mode check present" \
  || _fail "template-sync: no author_mode check"

echo "  --- placeholder substitution logic ---"
grep -q "GITHUB_USER" "$SYNCER" && grep -q "WORKSPACE_NAME" "$SYNCER" \
  && _pass "template-sync: placeholder substitution present" \
  || _fail "template-sync: no placeholder substitution"

echo "  --- post-sync validation call ---"
grep -q "validate-template" "$SYNCER" \
  && _pass "template-sync: post-sync validation present" \
  || _fail "template-sync: no post-sync validation"

echo "  --- post-sync instructions ---"
grep -q "git add.*git commit" "$SYNCER" \
  && _pass "template-sync: post-sync commit instructions present" \
  || _fail "template-sync: no commit instructions"

echo "  --- file mapping ---"
# Check that key files are in the SYNC_FILES map
grep -q "CLAUDE.md.*CLAUDE.md" "$SYNCER" \
  && _pass "template-sync: CLAUDE.md mapped" \
  || _fail "template-sync: CLAUDE.md not mapped"
grep -q "ONTOLOGY.md.*ONTOLOGY.md" "$SYNCER" \
  && _pass "template-sync: ONTOLOGY.md mapped" \
  || _fail "template-sync: ONTOLOGY.md not mapped"
grep -q "CHANGELOG.md.*CHANGELOG.md" "$SYNCER" \
  && _pass "template-sync: CHANGELOG.md mapped" \
  || _fail "template-sync: CHANGELOG.md not mapped"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
