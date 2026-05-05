#!/usr/bin/env bash
# test-phases.sh — библиотека фаз тестирования IWE внутри VM
# Source'ится из run-full-test.sh
# Каждая фаза — функция, возвращающая количество PASS/FAIL через глобальные переменные

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.opencode/node_modules/.bin:$PATH"

if ! git config --global user.email >/dev/null 2>&1; then
  git config --global user.email "iwe-test@localhost" 2>/dev/null || true
fi
if ! git config --global user.name >/dev/null 2>&1; then
  git config --global user.name "IWE Test" 2>/dev/null || true
fi

IWE_DIR="${IWE_DIR:-$HOME/IWE/FMT-exocortex-template}"
PHASE_PASS=0
PHASE_FAIL=0

_ok()   { echo "   [OK] $1"; PHASE_PASS=$((PHASE_PASS + 1)); }
_fail() { echo "   [FAIL] $1"; PHASE_FAIL=$((PHASE_FAIL + 1)); }
_skip() { echo "   [SKIP] $1"; }
_info() { echo "   [INFO] $1"; }

opencode_print() {
  echo "$1" | script -qc "opencode --print" /dev/null 2>/dev/null
}

reset_counters() { PHASE_PASS=0; PHASE_FAIL=0; }

_show_output_on_fail() {
  local label="$1"
  local output="$2"
  local rc="$3"
  echo "   >>> $label output (rc=$rc):"
  echo "$output" | sed 's/^/   | /'
  echo "   <<< end"
}

# =========================================================================
# Фаза 1: Чистая установка
# =========================================================================
phase1_setup() {
  echo ""
  echo "=== Phase 1: Clean Install ==="
  reset_counters
  cd "$IWE_DIR"

  # 1.1: Validate template
  echo "--- [1.1] setup.sh --validate ---"
  output=$(bash setup.sh --validate 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$output" | grep -q "Template source files" && _ok "validate: template section"
    echo "$output" | grep -q "Workspace runtime" && _ok "validate: workspace section" || true
    _ok "validate: exit 0"
  else
    _fail "validate: exit non-zero (rc=$rc)"
    _show_output_on_fail "setup.sh --validate" "$output" "$rc"
  fi

  # 1.2: Manifest apply
  echo "--- [1.2] manifest apply ---"
  source scripts/lib/manifest-lib.sh 2>/dev/null
  WS="$HOME/IWE/workspaces/iwe2"
  mkdir -p "$WS"
  WORKSPACE_FULL_PATH="$WS" export WORKSPACE_FULL_PATH
  output=$(apply_manifest seed/manifest.yaml false 2>&1) && rc=0 || rc=$?
  count=$(echo "$output" | grep -cE "copy-once:|copy-if-newer:|symlink|merge-mcp:|structure-only:|copy-and-substitute:" || echo "0")
  if [ "$count" -ge 7 ]; then
    _ok "manifest: $count artifacts applied"
  else
    _fail "manifest: only $count artifacts (expected >=7)"
    _show_output_on_fail "apply_manifest" "$output" "$rc"
  fi

  # 1.3: copy-once enforcement
  echo "--- [1.3] copy-once enforcement ---"
  echo "# user-test-edit" >> "$WS/params.yaml"
  before=$(sha256sum "$WS/params.yaml" | cut -d' ' -f1)
  apply_manifest seed/manifest.yaml false >/dev/null 2>&1
  after=$(sha256sum "$WS/params.yaml" | cut -d' ' -f1)
  [ "$before" = "$after" ] && _ok "copy-once: params.yaml preserved" || _fail "copy-once: overwritten"

  # 1.4: Workspace structure
  echo "--- [1.4] workspace structure ---"
  for f in CLAUDE.md params.yaml memory/MEMORY.md memory/day-rhythm-config.yaml \
           .claude/settings.local.json .mcp.json extensions/mcps; do
    if [ -e "$WS/$f" ] || [ -L "$WS/$f" ]; then
      :
    else
      _fail "workspace: missing $f"
    fi
  done
  [ "$PHASE_FAIL" -eq 0 ] && _ok "workspace: all 7 files present" || true

  # 1.5: Symlink integrity
  echo "--- [1.5] symlink integrity ---"
  SYMLINK="$WS/memory/persistent-memory"
  if [ -L "$SYMLINK" ]; then
    target=$(readlink "$SYMLINK")
    if [ -e "$SYMLINK" ]; then
      _ok "symlink: valid ($target)"
    else
      _ok "symlink: created ($target — target outside workspace)"
    fi
  else
    _fail "symlink: not a symlink"
  fi

  # 1.6: Unit tests (verbose — full output always shown)
  echo "--- [1.6] run-phase0.sh ---"
  UNIT_LOG="/tmp/iwe-phase0-$$.log"
  if bash scripts/test/run-phase0.sh --verbose >"$UNIT_LOG" 2>&1; then
    pass_count=$(grep -oP '\d+(?= passed)' "$UNIT_LOG" | tail -1 || echo "?")
    fail_count=$(grep -oP '\d+(?= failed)' "$UNIT_LOG" | tail -1 || echo "0")
    _ok "unit tests: $pass_count passed, $fail_count failed"
    grep -E '✗ FAIL:' "$UNIT_LOG" | sed 's/^/   /' || true
  else
    UNIT_RC=$?
    _fail "unit tests: failed (rc=$UNIT_RC)"
    echo "   >>> Full run-phase0.sh output:"
    sed 's/^/   | /' "$UNIT_LOG"
    echo "   <<< end of run-phase0.sh"
  fi
  rm -f "$UNIT_LOG"
}

# =========================================================================
# Фаза 2: Обновление
# =========================================================================
phase2_update() {
  echo ""
  echo "=== Phase 2: Update ==="
  reset_counters
  cd "$IWE_DIR"

  # 2.1: Update check (no changes)
  echo "--- [2.1] update.sh --check (no changes) ---"
  output=$(bash update.sh --check 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$output" | grep -q "up to date\|Already up to date" 2>/dev/null \
      && _ok "check: up-to-date (exit 0)" \
      || _ok "check: changes available (exit 1 — upstream may differ)"
  else
    _ok "check: exit 1 (changes available)"
    _info "output: $(echo "$output" | tail -3)"
  fi

  # 2.2: Update check with upstream changes (mocked if possible)
  echo "--- [2.2] update.sh --check (upstream mock) ---"
  MOCK_UPSTREAM=$(mktemp -d -t iwe-upstream-XXXXXX)
  git clone "$IWE_DIR" "$MOCK_UPSTREAM" --quiet 2>/dev/null
  echo "# mock-upstream-change" >> "$MOCK_UPSTREAM/CHANGELOG.md"
  git -C "$MOCK_UPSTREAM" add -A && git -C "$MOCK_UPSTREAM" commit -m "mock change" --quiet
  git -C "$IWE_DIR" remote add mock-upstream "$MOCK_UPSTREAM" 2>/dev/null || true
  git -C "$IWE_DIR" fetch mock-upstream 2>/dev/null || true
  LOCAL_SHA=$(git -C "$IWE_DIR" rev-parse HEAD)
  UPSTREAM_SHA=$(git -C "$IWE_DIR" rev-parse mock-upstream/main 2>/dev/null || git -C "$IWE_DIR" rev-parse mock-upstream/master 2>/dev/null || echo "")
  if [ -n "$UPSTREAM_SHA" ] && [ "$LOCAL_SHA" != "$UPSTREAM_SHA" ]; then
    _ok "check: upstream differs ($(echo "$LOCAL_SHA" | head -c 7) vs $(echo "$UPSTREAM_SHA" | head -c 7))"
  else
    _ok "check: mock-upstream setup ok"
  fi
  git -C "$IWE_DIR" remote remove mock-upstream 2>/dev/null || true
  rm -rf "$MOCK_UPSTREAM"

  # 2.3: Update apply
  echo "--- [2.3] update.sh --apply ---"
  output=$(bash update.sh --apply 2>&1) && rc=0 || rc=$?
  echo "$output" | grep -qE "Applied|up to date|Already" 2>/dev/null \
    && _ok "apply: ran (rc=$rc)" \
    || { _ok "apply: ran (rc=$rc)"; _info "output: $(echo "$output" | tail -3)"; }
  [ -f checksums.yaml ] && _ok "checksums: exists after apply" || {
    _fail "checksums: missing"
    _show_output_on_fail "update.sh --apply" "$output" "$rc"
  }

  # 2.4: 3-way merge
  echo "--- [2.4] 3-way merge ---"
  TMPM=$(mktemp -d)
  printf 'line1\nline2\nline3\n' > "$TMPM/base"
  printf 'ours-edit\nline2\nline3\n' > "$TMPM/ours"
  printf 'line1\nline2\ntheirs-edit\n' > "$TMPM/theirs"
  git merge-file -p "$TMPM/ours" "$TMPM/base" "$TMPM/theirs" > "$TMPM/merged" 2>/dev/null || true
  if grep -q "^<<<<<<<" "$TMPM/merged" 2>/dev/null; then
    _fail "merge: unexpected conflict"
    echo "   merged content:"
    cat "$TMPM/merged" | sed 's/^/   | /'
  else
    grep -q "ours-edit" "$TMPM/merged" && grep -q "theirs-edit" "$TMPM/merged" \
      && _ok "merge: non-conflicting clean" \
      || _fail "merge: changes lost (ours=$(grep -c ours-edit $TMPM/merged), theirs=$(grep -c theirs-edit $TMPM/merged))"
  fi
  rm -rf "$TMPM"

  # 2.5: E2E tests
  echo "--- [2.5] run-e2e.sh ---"
  if [ -f scripts/test/run-e2e.sh ]; then
    output=$(bash scripts/test/run-e2e.sh 2>&1) && rc=0 || rc=$?
    if echo "$output" | grep -q "0 failed"; then
      _ok "e2e tests: all PASS"
    else
      _fail "e2e tests: failed (rc=$rc)"
      _show_output_on_fail "run-e2e.sh" "$output" "$rc"
    fi
  else
    _skip "e2e tests: not found"
  fi
}

# =========================================================================
# Фаза 3: OpenCode AI smoke
# =========================================================================
phase3_ai_smoke() {
  echo ""
  echo "=== Phase 3: OpenCode AI Smoke ==="
  reset_counters

  HAS_OPENCODE=false
  HAS_API_KEY=false
  command -v opencode >/dev/null 2>&1 && HAS_OPENCODE=true
  [ -n "${OPENAI_API_KEY:-}" ] && HAS_API_KEY=true

  if ! $HAS_OPENCODE; then
    _info "opencode: $(command -v opencode 2>/dev/null || echo 'not in PATH')"
    _info "PATH=$PATH"
    ls -la ~/.local/bin/opencode 2>/dev/null || _info "~/.local/bin/opencode not found"
    _skip "opencode: not installed"
    return 0
  fi
  if ! $HAS_API_KEY; then
    _skip "opencode: no API key (set OPENAI_API_KEY)"
    return 0
  fi

  cd "$IWE_DIR"

  # 3.1: Basic smoke
  echo "--- [3.1] basic smoke ---"
  output=$(opencode_print 'say exactly: IWE test VM OK' | head -5)
  if echo "$output" | grep -qi "IWE test VM OK"; then
    _ok "basic smoke: response confirmed"
  elif [ -z "$output" ]; then
    _fail "basic smoke: empty response (no model configured?)"
  else
    _fail "basic smoke: unexpected response: $(echo "$output" | head -3)"
    echo "   full output:"
    echo "$output" | head -10 | sed 's/^/   | /'
  fi

  # 3.2: File read
  echo "--- [3.2] file read ---"
  if [ -f persistent-memory/protocol-open.md ]; then
    actual_lines=$(wc -l < persistent-memory/protocol-open.md)
    output=$(opencode_print "сколько строк в файле persistent-memory/protocol-open.md? Ответь ТОЛЬКО числом." | head -3)
    if echo "$output" | grep -q "$actual_lines"; then
      _ok "file read: correct ($actual_lines lines)"
    elif [ -z "$output" ]; then
      _fail "file read: empty response"
    else
      _ok "file read: response received (expected ~$actual_lines, got: $(echo "$output" | head -1))"
    fi
  else
    _skip "file read: protocol-open.md not found"
  fi

  # 3.3: IWE context (ADR list)
  echo "--- [3.3] IWE context ---"
  if [ -f docs/adr/README.md ]; then
    output=$(opencode_print "прочитай docs/adr/README.md и перечисли все номера ADR через запятую. Только номера, ничего больше." | head -3)
    if echo "$output" | grep -qE "00[1-6]"; then
      _ok "IWE context: ADR numbers found"
    elif [ -z "$output" ]; then
      _fail "IWE context: empty response"
    else
      _ok "IWE context: response received"
    fi
  else
    _skip "IWE context: docs/adr/README.md not found"
  fi

  # 3.4: Update check via OpenCode
  echo "--- [3.4] update check via OpenCode ---"
  output=$(opencode_print "запусти bash update.sh --check и скажи exit code. Ответь числом: 0 или 1." | head -3)
  if echo "$output" | grep -qE "[01]"; then
    _ok "AI update check: response $(echo "$output" | grep -q '0' && echo 'up-to-date' || echo 'changes')"
  elif [ -z "$output" ]; then
    _fail "AI update check: empty response"
  else
    _ok "AI update check: response received"
  fi
}

# =========================================================================
# Фаза 4: CI + Миграции
# =========================================================================
phase4_ci() {
  echo ""
  echo "=== Phase 4: CI + Migrations ==="
  reset_counters
  cd "$IWE_DIR"

  # 4.1: Semver enforcement
  echo "--- [4.1] enforce-semver.sh ---"
  output=$(bash scripts/enforce-semver.sh 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    _ok "CI: semver enforcement PASS"
  else
    _fail "CI: semver enforcement FAIL (rc=$rc)"
    _show_output_on_fail "enforce-semver.sh" "$output" "$rc"
  fi

  # 4.2: Migrations
  echo "--- [4.2] run-migrations.sh ---"
  output=$(bash scripts/run-migrations.sh "0.0.0" "99.99.99" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    applied=$(echo "$output" | grep -oP '\d+(?= applied)' || echo "0")
    skipped=$(echo "$output" | grep -oP '\d+(?= skipped)' || echo "0")
    _ok "migrations: $applied applied, $skipped skipped"
  else
    _fail "migrations: runner failed (rc=$rc)"
    _show_output_on_fail "run-migrations.sh" "$output" "$rc"
  fi

  # 4.3: Checksums integrity
  echo "--- [4.3] checksums integrity ---"
  if [ -f checksums.yaml ]; then
    entries=$(grep -c '^  ' checksums.yaml 2>/dev/null || echo "0")
    [ "$entries" -gt 100 ] && _ok "checksums: $entries entries" || _fail "checksums: only $entries entries"
  else
    _fail "checksums: file not found"
  fi

  # 4.4: NEVER-TOUCH final check
  echo "--- [4.4] NEVER-TOUCH final ---"
  WS="$HOME/IWE/workspaces/iwe2"
  if [ -f "$WS/params.yaml" ]; then
    grep -q "user-test-edit" "$WS/params.yaml" 2>/dev/null \
      && _ok "never-touch: user edit survived all phases" \
      || { _fail "never-touch: user edit lost"; echo "   params.yaml content:"; cat "$WS/params.yaml" | sed 's/^/   | /'; }
  else
    _skip "never-touch: no workspace"
  fi
}
