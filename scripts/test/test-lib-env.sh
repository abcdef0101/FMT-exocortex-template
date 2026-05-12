#!/usr/bin/env bash
# test-lib-env.sh — тесты lib/lib-env.sh (env loading, workspace resolution, validation)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail()  { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

LIB_ENV="$ROOT_DIR/lib/lib-env.sh"

echo "  --- syntax check ---"
bash -n "$LIB_ENV" \
  && _pass "lib-env.sh bash syntax ok" \
  || _fail "lib-env.sh syntax error"

TMPDIR=$(mktemp -d -t lib-env-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

source "$LIB_ENV" 2>/dev/null || { _fail "cannot source lib/lib-env.sh"; exit 1; }

echo "  --- iwe_find_repo_root ---"

# Create a mock repo structure
mkdir -p "$TMPDIR/workspaces/test-ws/memory"
echo "fake" > "$TMPDIR/workspaces/test-ws/CLAUDE.md"
echo "fake" > "$TMPDIR/workspaces/test-ws/memory/navigation.md"

result=$(iwe_find_repo_root "$TMPDIR/workspaces/test-ws")
[ "$result" = "$TMPDIR/workspaces/test-ws" ] \
  && _pass "find_repo_root: finds repo with CLAUDE.md + memory/" \
  || _fail "find_repo_root: expected $TMPDIR/workspaces/test-ws, got $result"

result=$(iwe_find_repo_root "$TMPDIR/workspaces/test-ws/memory")
[ "$result" = "$TMPDIR/workspaces/test-ws" ] \
  && _pass "find_repo_root: walks up from subdirectory" \
  || _fail "find_repo_root from subdir: expected $TMPDIR/workspaces/test-ws, got $result"

# Create dir without CLAUDE.md
mkdir -p "$TMPDIR/no-repo/sub/deep"
if iwe_find_repo_root "$TMPDIR/no-repo/sub/deep"; then
  _fail "find_repo_root: should fail for non-repo directory"
else
  _pass "find_repo_root: returns 1 for non-repo directory"
fi

echo "  --- iwe_workspace_dir_from_repo_root ---"

result=$(iwe_workspace_dir_from_repo_root "$TMPDIR/workspaces/test-ws")
[ "$result" = "$TMPDIR/workspaces" ] \
  && _pass "workspace_dir: returns parent of repo root" \
  || _fail "workspace_dir: expected $TMPDIR/workspaces, got $result"

echo "  --- iwe_env_file_from_repo_root ---"

# Verify it prints the path (format depends on HOME)
result=$(iwe_env_file_from_repo_root "$TMPDIR/workspaces/test-ws")
echo "$result" | grep -q "env$" \
  && _pass "env_file: path ends with /env" \
  || _fail "env_file: unexpected path: $result"

echo "  --- iwe_validate_env_file ---"

# Valid env file
cat > "$TMPDIR/valid-env" <<'EOF'
export FOO=bar
export BAR=baz
EOF
if iwe_validate_env_file "$TMPDIR/valid-env"; then
  _pass "validate: clean env file passes"
else
  _fail "validate: clean env file should pass"
fi

# Dangerous env file with eval
cat > "$TMPDIR/eval-env" <<'EOF'
eval something
export FOO=bar
EOF
if iwe_validate_env_file "$TMPDIR/eval-env"; then
  _fail "validate: env file with eval should fail"
else
  _pass "validate: env file with eval rejected"
fi

# Dangerous env file with source
cat > "$TMPDIR/source-env" <<'EOF'
source /bad/path
export FOO=bar
EOF
if iwe_validate_env_file "$TMPDIR/source-env"; then
  _fail "validate: env file with source should fail"
else
  _pass "validate: env file with source rejected"
fi

# Dangerous env file with dot-source
cat > "$TMPDIR/dot-env" <<'EOF'
. /some/file
export FOO=bar
EOF
if iwe_validate_env_file "$TMPDIR/dot-env"; then
  _fail "validate: env file with dot-source should fail"
else
  _pass "validate: env file with dot-source rejected"
fi

# Empty env file
cat > "$TMPDIR/empty-env" <<'EOF'

EOF
if iwe_validate_env_file "$TMPDIR/empty-env"; then
  _pass "validate: empty env file passes"
else
  _fail "validate: empty env file should pass"
fi

echo "  --- iwe_load_env_file ---"

# Valid env with known variable
cat > "$TMPDIR/loadable-env" <<'EOF'
export IWE_TEST_VAR_12345="testvalue"
EOF
iwe_load_env_file "$TMPDIR/loadable-env" 2>/dev/null
[ "${IWE_TEST_VAR_12345:-}" = "testvalue" ] \
  && _pass "load_env: exports variables from env file" \
  || _fail "load_env: variable not exported (got '${IWE_TEST_VAR_12345:-}')"

# Non-existent file
if iwe_load_env_file "$TMPDIR/nonexistent-env" 2>/dev/null; then
  _fail "load_env: should fail for nonexistent file"
else
  _pass "load_env: fails for nonexistent file"
fi

echo "  --- iwe_require_env_vars ---"

# Required var present
export IWE_REQUIRED_TEST="present"
if iwe_require_env_vars "IWE_REQUIRED_TEST" 2>/dev/null; then
  _pass "require_env: passes when var is set"
else
  _fail "require_env: should pass when var is set"
fi

# Required var missing
if iwe_require_env_vars "IWE_NONEXISTENT_VAR_XYZ" 2>/dev/null; then
  _fail "require_env: should fail when var is unset"
else
  _pass "require_env: fails when var is unset"
fi

# Multiple vars
export IWE_VAR1="a"
export IWE_VAR2="b"
if iwe_require_env_vars "IWE_VAR1" "IWE_VAR2" 2>/dev/null; then
  _pass "require_env: passes when all vars set"
else
  _fail "require_env: should pass when all vars set"
fi

echo "  --- idempotent source guard ---"
source "$LIB_ENV" 2>/dev/null \
  && _pass "source: idempotent (second source succeeds silently)" \
  || _fail "source: not idempotent"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
