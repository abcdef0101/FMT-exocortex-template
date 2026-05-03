#!/usr/bin/env bash
# test-never-touch.sh — проверка NEVER-TOUCH enforcement (cross-cutting)
# ADR-005 §2 checksum enforcement, §9 NEVER-TOUCH
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- checksums.yaml never_touch list ---"
CK_FILE="$ROOT_DIR/checksums.yaml"
if [ -f "$CK_FILE" ]; then
  nt_entries=$(sed -n '/^never_touch:/,/^files:/p' "$CK_FILE" | grep '^  - ' | sed 's/  - //')

  # Check all 6 expected NEVER-TOUCH entries
  check_nt() {
    local pattern="$1" label="$2"
    if echo "$nt_entries" | grep -q "$pattern"; then
      _pass "never_touch: $label"
    else
      _fail "never_touch: $label (missing: $pattern)"
    fi
  }
  check_nt "seed/MEMORY.md" "seed/MEMORY.md"
  check_nt "seed/params.yaml" "seed/params.yaml"
  check_nt "seed/day-rhythm" "seed/day-rhythm-config.yaml"
  check_nt "seed/settings" "seed/settings.local.json"
  check_nt "workspaces/" "workspaces/"
  check_nt "extensions/" "extensions/"
fi

echo "  --- manifest.yaml copy-once strategies ---"
MANIFEST_FILE="$ROOT_DIR/seed/manifest.yaml"
if [ -f "$MANIFEST_FILE" ]; then
  # Files with copy-once strategy = user data, never overwritten
  copy_once=$(grep -B3 'copy-once' "$MANIFEST_FILE" | grep 'target:' | sed 's/.*: //')
  [ -n "$copy_once" ] \
    && _pass "manifest: copy-once applied to $(echo "$copy_once" | wc -l) targets" \
    || _fail "manifest: no copy-once strategies"
fi

echo "  --- update.sh never-touch integration ---"
UPDATER="$ROOT_DIR/update.sh"
if [ -f "$UPDATER" ]; then
  # Check that update.sh reads checksums.yaml
  grep -q "never_touch\|NEVER.TOUCH\|never-touch" "$UPDATER" 2>/dev/null \
    && _pass "update.sh: never-touch logic present" \
    || _fail "update.sh: no never-touch logic"
fi

echo "  --- checksums: never-touch files not in files section ---"
if [ -f "$CK_FILE" ]; then
  files_section=$(sed -n '/^files:/,$ p' "$CK_FILE" | grep '^  ' | sed 's/^  //' | cut -d: -f1 | sed 's/^ *//')
  nt_violations=0
  while IFS= read -r nt; do
    [ -z "$nt" ] && continue
    if echo "$files_section" | grep -qxF "$nt" 2>/dev/null; then
      _fail "file section contains never-touch: $nt"
      nt_violations=$((nt_violations + 1))
    fi
  done <<< "$nt_entries"
  [ "$nt_violations" -eq 0 ] \
    && _pass "checksums: 0 never-touch files in files section" \
    || true
fi

echo "  --- setup.sh sources manifest-lib ---"
SETUP="$ROOT_DIR/setup.sh"
if [ -f "$SETUP" ]; then
  grep -q "manifest-lib.sh" "$SETUP" \
    && _pass "setup.sh: manifest-lib sourced" \
    || _fail "setup.sh: manifest-lib not sourced"
fi

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
