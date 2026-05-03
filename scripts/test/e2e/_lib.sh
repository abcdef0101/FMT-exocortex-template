#!/usr/bin/env bash
# _lib.sh — E2E test helpers
# Source this file from E2E test scripts

UPSTREAM_DIR=""    # populated by setup_upstream()
LOCAL_DIR=""       # populated by setup_local()
WS_DIR=""          # populated by setup_workspace()
ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SETUP="$ROOT_DIR/setup.sh"
UPDATE_SH="$ROOT_DIR/update.sh"
MANIFEST_LIB="$ROOT_DIR/scripts/lib/manifest-lib.sh"

# === Test scaffolding ===
E2E_PASS=0
E2E_FAIL=0

e2e_pass() { echo "  ✓ $1"; E2E_PASS=$((E2E_PASS + 1)); }
e2e_fail() { echo "  ✗ $1"; E2E_FAIL=$((E2E_FAIL + 1)); }

e2e_done() {
  echo "  E2E: $E2E_PASS passed, $E2E_FAIL failed"
  return $E2E_FAIL
}

# === Repo operations ===
setup_upstream() {
  UPSTREAM_DIR=$(mktemp -d -t e2e-upstream-XXXXXX)
  git clone "$ROOT_DIR" "$UPSTREAM_DIR" --quiet 2>/dev/null
  [ -d "$UPSTREAM_DIR/.git" ] || { echo "E2E: upstream clone failed" >&2; exit 1; }
  # Ensure main branch exists
  (cd "$UPSTREAM_DIR" && git branch -f main HEAD 2>/dev/null) || true
  echo "  • upstream: $UPSTREAM_DIR"
  return 0
}

setup_local() {
  LOCAL_DIR=$(mktemp -d -t e2e-local-XXXXXX)
  local src="${1:-$UPSTREAM_DIR}"
  git clone "$src" "$LOCAL_DIR" --quiet 2>/dev/null
  [ -d "$LOCAL_DIR/.git" ] || { echo "E2E: local clone failed" >&2; exit 1; }
  echo "  • local: $LOCAL_DIR"
  return 0
}

inject_change() {
  local repo="$1"
  local file="$2"
  local content="$3"
  echo "$content" >> "$repo/$file"
  (cd "$repo" && git add "$file" && git commit -m "e2e: inject change" --quiet)
  (cd "$repo" && git branch -f main HEAD 2>/dev/null) || true
}

repoint_origin() {
  local local_repo="$1"
  local upstream_repo="$2"
  git -C "$local_repo" remote set-url origin "$upstream_repo"
}

# === Workspace creation ===
setup_workspace() {
  local base_dir="$1"
  WS_DIR="$base_dir/mock-workspace"
  mkdir -p "$WS_DIR"
  export WORKSPACE_FULL_PATH="$WS_DIR"
  echo "  • workspace: $WS_DIR"
  return 0
}

# === Verification helpers ===
verify_workspace_structure() {
  local ws="$1"
  local errors=0

  check() { [ -e "$ws/$1" ] || [ -L "$ws/$1" ] || { e2e_fail "missing: $1"; errors=$((errors + 1)); }; }

  check "CLAUDE.md"
  check "params.yaml"
  check "memory/"
  check "memory/MEMORY.md"
  check "memory/day-rhythm-config.yaml"
  check ".claude/settings.local.json"
  check ".mcp.json"
  check "extensions/mcps"
  check "memory/persistent-memory"  # symlink — use -L
  return $errors
}

verify_symlink() {
  local ws="$1"
  local link="$ws/memory/persistent-memory"
  [ -L "$link" ] || { e2e_fail "symlink: not a symlink"; return 1; }
  # Target may not exist in temp dirs (relative path ../../../persistent-memory)
  # — verify that the symlink was at least created
  local target
  target=$(readlink "$link")
  e2e_pass "symlink: created (target=$target$([ -e "$link" ] && echo ', valid' || echo ', target outside temp dir'))"
  return 0
}

verify_never_touch() {
  local file="$1"
  local expected_pattern="$2"
  grep -q "$expected_pattern" "$file" 2>/dev/null \
    && e2e_pass "never-touch: $(basename "$file") preserved ($expected_pattern)" \
    || e2e_fail "never-touch: $(basename "$file") overwritten"
}

verify_checksums() {
  local ck_file="$1"
  [ -f "$ck_file" ] || { e2e_fail "checksums.yaml: missing"; return 1; }
  local count
  count=$(grep -c '^  ' "$ck_file" 2>/dev/null || echo "0")
  [ "$count" -gt 100 ] \
    && e2e_pass "checksums.yaml: $count entries" \
    || e2e_fail "checksums.yaml: only $count entries (expected >100)"
}

# === Cleanup ===
e2e_cleanup() {
  [ -n "${UPSTREAM_DIR:-}" ] && rm -rf "$UPSTREAM_DIR" 2>/dev/null || true
  [ -n "${LOCAL_DIR:-}" ] && rm -rf "$LOCAL_DIR" 2>/dev/null || true
  [ -n "${WS_DIR:-}" ] && rm -rf "$WS_DIR" 2>/dev/null || true
}

trap e2e_cleanup EXIT
