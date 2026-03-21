#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SETUP_LIB_VALIDATE_TEMPLATE_LOADED:-}" ]]; then
  return 0
fi
readonly _SETUP_LIB_VALIDATE_TEMPLATE_LOADED=1

function validate_template_grep_count() {
  local pattern="$1"
  shift
  grep -rn "$pattern" "$@" 2>/dev/null | wc -l | tr -d ' ' || true
}

function validate_template_check_author_content() {
  local template_dir="$1"
  local check_failed=0
  local count pattern

  echo -n "[1/5] Author-specific content... "
  for pattern in "tserentserenov" "PACK-MIM" "aist_bot_newarchitecture" "DS-Knowledge-Index-Tseren"; do
    count=$(grep -rn "$pattern" "$template_dir" --include="*.md" --include="*.sh" \
      --include="*.json" --include="*.plist" --include="*.yaml" \
      --exclude='validate-template.sh' 2>/dev/null \
      | grep -v 'github.com/' | wc -l | tr -d ' ' || true)
    if [[ "$count" -gt 0 ]]; then
      [[ "$check_failed" -eq 0 ]] && echo "FAIL"
      echo "  Found '$pattern' in $count non-URL locations:"
      grep -rn "$pattern" "$template_dir" --include="*.md" --include="*.sh" \
        --include="*.json" --include="*.plist" \
        --exclude='validate-template.sh' 2>/dev/null | grep -v 'github.com/' | head -3 || true
      check_failed=1
    fi
  done
  [[ "$check_failed" -eq 0 ]] && echo "PASS"
  return "$check_failed"
}

function validate_template_check_users_paths() {
  local template_dir="$1"
  local count

  echo -n "[2/5] Hardcoded /Users/ paths... "
  count=$(grep -rn '/Users/' "$template_dir" --include="*.md" --include="*.sh" \
    --include="*.json" --include="*.plist" \
    --exclude='validate-template.sh' --exclude='setup.sh' 2>/dev/null \
    | grep -v '/Users/\.\.\./' | wc -l | tr -d ' ' || true)
  if [[ "$count" -gt 0 ]]; then
    echo "FAIL ($count hits)"
    grep -rn '/Users/' "$template_dir" --include="*.md" --include="*.sh" \
      --exclude='validate-template.sh' --exclude='setup.sh' 2>/dev/null \
      | grep -v '/Users/\.\.\./' | head -3 || true
    return 1
  fi
  echo "PASS"
  return 0
}

function validate_template_check_homebrew_paths() {
  local template_dir="$1"
  local count

  echo -n "[3/5] Hardcoded /opt/homebrew paths... "
  count=$(grep -rn '/opt/homebrew' "$template_dir" --include="*.md" --include="*.sh" \
    --include="*.json" --include="*.plist" \
    --exclude='validate-template.sh' --exclude='setup.sh' 2>/dev/null \
    | grep -v 'README.md' \
    | grep -v 'validate-template.yml' \
    | grep -v '/usr/local/bin.*:/opt/homebrew' \
    | wc -l | tr -d ' ' || true)
  if [[ "$count" -gt 0 ]]; then
    echo "FAIL ($count hits)"
    grep -rn '/opt/homebrew' "$template_dir" --include="*.md" --include="*.sh" \
      --exclude='validate-template.sh' --exclude='setup.sh' 2>/dev/null \
      | grep -v 'README.md' | grep -v 'validate-template.yml' | head -3 || true
    return 1
  fi
  echo "PASS"
  return 0
}

function validate_template_check_memory_skeleton() {
  local template_dir="$1"
  local memory_file rp_rows

  echo -n "[4/5] MEMORY.md is skeleton... "
  memory_file="$template_dir/memory/MEMORY.md"
  if [[ -f "$memory_file" ]]; then
    rp_rows=$(grep -c '^|' "$memory_file" 2>/dev/null || echo 0)
    if [[ "$rp_rows" -gt 15 ]]; then
      echo "FAIL ($rp_rows table rows, expected ≤15)"
      return 1
    fi
    echo "PASS ($rp_rows rows)"
    return 0
  fi

  echo "WARN (file missing)"
  return 1
}

function validate_template_check_required_files() {
  local template_dir="$1"
  local missing=0 required_file

  echo -n "[5/5] Required files... "
  for required_file in CLAUDE.md ONTOLOGY.md README.md \
    memory/MEMORY.md memory/hard-distinctions.md \
    memory/protocol-open.md memory/protocol-close.md \
    memory/navigation.md \
    roles/strategist/scripts/strategist.sh; do
    if [[ ! -f "$template_dir/$required_file" ]]; then
      echo ""
      echo "  MISSING: $required_file"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] && echo "PASS"
  return "$missing"
}
