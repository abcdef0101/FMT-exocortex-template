#!/usr/bin/env bash
# test-checksums.sh — проверка репродуцируемости и целостности checksums.yaml
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

GEN_SCRIPT="$ROOT_DIR/scripts/generate-checksums.sh"
CK_FILE="$ROOT_DIR/checksums.yaml"

[ -f "$GEN_SCRIPT" ] || { _fail "generate-checksums.sh not found"; exit 1; }
[ -f "$CK_FILE" ]   || { _fail "checksums.yaml not found"; exit 1; }

# -------------------------------------------------------------------
echo "  --- idempotency ---"

bash "$GEN_SCRIPT" 2>/dev/null
cp "$CK_FILE" /tmp/checksums-first.yaml
bash "$GEN_SCRIPT" 2>/dev/null
cp "$CK_FILE" /tmp/checksums-second.yaml
# Strip volatile 'generated:' field before comparison
diff <(grep -v '^generated:' /tmp/checksums-first.yaml) <(grep -v '^generated:' /tmp/checksums-second.yaml) \
  && _pass "regenerate is idempotent" \
  || _fail "regenerate is idempotent (content differs between two runs)"
rm -f /tmp/checksums-first.yaml /tmp/checksums-second.yaml

# -------------------------------------------------------------------
echo "  --- never_touch exclusion ---"

# Extract never_touch list
never_touch_entries=$(sed -n '/^never_touch:/,/^files:/p' "$CK_FILE" | grep '^  - ' | sed 's/  - //')
files_entries=$(sed -n '/^files:/,$ p' "$CK_FILE" | grep '^  ' | sed 's/^  //' | cut -d: -f1 | sed 's/^ *//')

nt_violations=0
while IFS= read -r nt; do
  [ -z "$nt" ] && continue
  # Check: no file entry starts with a never_touch pattern
  if echo "$files_entries" | grep -q "^$nt"; then
    _fail "never_touch violation: $nt found in files section"
    nt_violations=$((nt_violations + 1))
  fi
done <<< "$never_touch_entries"
[ "$nt_violations" -eq 0 ] \
  && _pass "never_touch entries excluded from files ($(echo "$never_touch_entries" | wc -l) entries)" \
  || true

# -------------------------------------------------------------------
echo "  --- coverage checks ---"

# Persistent-memory (excluding MANIFEST.yaml, including it separately if needed)
pm_files=$(echo "$files_entries" | grep '^persistent-memory/' | grep -v MANIFEST.yaml | wc -l)
[ "$pm_files" -ge 10 ] \
  && _pass "persistent-memory coverage: $pm_files files" \
  || _fail "persistent-memory coverage: expected >=10, got $pm_files"

# Skills (SKILL.md files)
skill_files=$(echo "$files_entries" | grep '\.claude/skills/.*/SKILL.md' | wc -l)
[ "$skill_files" -ge 17 ] \
  && _pass "skills SKILL.md coverage: $skill_files files" \
  || _fail "skills SKILL.md coverage: expected >=17, got $skill_files"

# Hooks
hook_files=$(echo "$files_entries" | grep '\.claude/hooks/.*\.sh' | wc -l)
[ "$hook_files" -ge 6 ] \
  && _pass "hooks coverage: $hook_files files" \
  || _fail "hooks coverage: expected >=6, got $hook_files"

# -------------------------------------------------------------------
echo "  --- key files present ---"

for key in "CLAUDE.md" "CHANGELOG.md" "seed/manifest.yaml" "extension-points.yaml"; do
  if echo "$files_entries" | grep -qxF "$key"; then
    _pass "key file present: $key"
  else
    _fail "key file missing: $key (in files section)"
  fi
done

# -------------------------------------------------------------------
echo "  --- SHA-256 spot check ---"

# Normalize function inline (same as generator)
normalize() { sed 's/[[:space:]]*$//' "$1"; }

spot_check() {
  local f="$1"
  local expected
  expected=$(grep "^  $f:" "$CK_FILE" | sed 's/.*: *"//;s/"//' | head -1)
  local actual
  actual=$(normalize "$ROOT_DIR/$f" | sha256sum | cut -d' ' -f1)
  [ -n "$expected" ] && [ "$expected" = "$actual" ] \
    && _pass "SHA-256 match: $f" \
    || _fail "SHA-256 mismatch: $f (expected=$expected, actual=$actual)"
}

spot_check "CLAUDE.md"
spot_check "seed/manifest.yaml"
spot_check "CHANGELOG.md"

# P1 #5: orphan checksums — file in checksums.yaml not on disk
echo "  --- orphan checksums ---"
orphan_count=0
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*([^:]+): ]] || continue
  f="${BASH_REMATCH[1]}"
  f="${f#"${f%%[![:space:]]*}"}"
  f="${f%"${f##*[![:space:]]}"}"
  [ -z "$f" ] && continue
  [ -f "$ROOT_DIR/$f" ] && continue
  [ -d "$ROOT_DIR/$f" ] && continue
  # Skip never_touch patterns
  echo "$never_touch_entries" | grep -qxF "$f" 2>/dev/null && continue
  orphan_count=$((orphan_count + 1))
  _fail "orphan checksum entry: $f (not on disk)"
done < <(sed -n '/^files:/,$ p' "$CK_FILE" | grep '^  ')
[ "$orphan_count" -eq 0 ] \
  && _pass "orphan checksums: 0 entries" \
  || true

# -------------------------------------------------------------------
echo "  --- YAML validity ---"

validate_yaml_ruby() {
  local detail
  detail=$(ruby -ryaml -e "YAML.load_file('$CK_FILE')" 2>&1)
  if [ $? -eq 0 ]; then
    _pass "checksums.yaml is valid YAML (ruby)"
    return 0
  else
    echo "    ruby YAML error: $detail"
    return 1
  fi
}

validate_yaml_python() {
  local detail
  detail=$(python3 -c "import yaml; yaml.safe_load(open('$CK_FILE'))" 2>&1)
  if [ $? -eq 0 ]; then
    _pass "checksums.yaml is valid YAML (python3)"
    return 0
  else
    echo "    python3 YAML error: $detail"
    return 1
  fi
}

YAML_OK=false
if command -v python3 &>/dev/null; then
  validate_yaml_python && YAML_OK=true
fi
if ! $YAML_OK && command -v ruby &>/dev/null; then
  validate_yaml_ruby && YAML_OK=true
fi
if ! $YAML_OK; then
  if ! command -v python3 &>/dev/null && ! command -v ruby &>/dev/null; then
    echo "  - skipped YAML validation (no python3/ruby)"
  else
    _fail "checksums.yaml is invalid YAML"
    echo "    first 10 lines:"
    head -10 "$CK_FILE" | sed 's/^/    /'
    echo "    ..."
    echo "    last 5 lines:"
    tail -5 "$CK_FILE" | sed 's/^/    /'
  fi
fi

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
