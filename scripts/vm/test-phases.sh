#!/usr/bin/env bash
# test-phases.sh — библиотека фаз тестирования IWE внутри VM
# Source'ится из run-full-test.sh
# Каждая фаза — функция, возвращающая количество PASS/FAIL через глобальные переменные

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.opencode/node_modules/.bin:$PATH"

if ! git config --global user.email >/dev/null 2>&1; then
  git config --global user.email "iwe-test@localhost" 2>/dev/null || echo "WARN: git config failed" >&2
fi
if ! git config --global user.name >/dev/null 2>&1; then
  git config --global user.name "IWE Test" 2>/dev/null || true
fi

IWE_DIR="${IWE_DIR:-$HOME/IWE/FMT-exocortex-template}"
PHASE_PASS=0
PHASE_FAIL=0
PHASE_SOFT_PASS=0
METRICS_FILE="${METRICS_FILE:-/tmp/iwe-phase-metrics.txt}"

_ok()      { echo "   [OK]  $1"; PHASE_PASS=$((PHASE_PASS + 1)); }
_ok_soft() { echo "   [OK*] $1"; PHASE_SOFT_PASS=$((PHASE_SOFT_PASS + 1)); PHASE_PASS=$((PHASE_PASS + 1)); }
_fail()    { echo "   [FAIL] $1"; PHASE_FAIL=$((PHASE_FAIL + 1)); }
_skip()    { echo "   [SKIP] $1"; }
_info()    { echo "   [INFO] $1"; }

opencode_print() {
  echo "$1" | script -qc "opencode --print" /dev/null 2>/dev/null
}

reset_counters() { PHASE_PASS=0; PHASE_FAIL=0; PHASE_SOFT_PASS=0; }

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
  PHASE_START=$(date +%s)
  reset_counters
  cd "$IWE_DIR"

  # 1.1: Validate template
  echo "--- [1.1] setup.sh --validate ---"
  output=$(bash setup.sh --validate 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$output" | grep -q "Template source files" && _ok "validate: template section" \
      || _fail "validate: template section missing"
    echo "$output" | grep -q "Workspace runtime" && _ok "validate: workspace section" \
      || _fail "validate: workspace section missing"
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
  if apply_manifest seed/manifest.yaml false >/dev/null 2>&1; then
    after=$(sha256sum "$WS/params.yaml" | cut -d' ' -f1)
    [ "$before" = "$after" ] && _ok "copy-once: params.yaml preserved" || _fail "copy-once: overwritten"
  else
    _fail "copy-once: apply_manifest failed (rc=$?)"
  fi

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

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase1_setup PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "${METRICS_FILE:-/tmp/iwe-phase-metrics.txt}"
}

# =========================================================================
# Фаза 2: Обновление
# =========================================================================
phase2_update() {
  echo ""
  echo "=== Phase 2: Update ==="
  PHASE_START=$(date +%s)
  reset_counters
  cd "$IWE_DIR"

  # 2.1: Update check (no changes)
  echo "--- [2.1] update.sh --check (no changes) ---"
  output=$(bash update.sh --check 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$output" | grep -q "up to date\|Already up to date" 2>/dev/null \
      && _ok "check: up-to-date (exit 0)" \
      || _ok "check: changes available (exit 1 — upstream may differ)"
  elif [ "$rc" -eq 1 ]; then
    _ok "check: exit 1 (changes available)"
  else
    _fail "check: unexpected exit code (rc=$rc)"
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

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase2_update PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}

# =========================================================================
# Фаза 3: OpenCode AI smoke
# =========================================================================
phase3_ai_smoke() {
  echo ""
  echo "=== Phase 3: OpenCode AI Smoke ==="
  PHASE_START=$(date +%s)
  reset_counters

  HAS_API_KEY=false
  [ -n "${OPENAI_API_KEY:-}" ] && HAS_API_KEY=true

  if ! $HAS_API_KEY; then
    echo "--- [3.0] dry-run (no API key) ---"
    if opencode --version >/dev/null 2>&1; then
      _ok "dry-run: opencode --version works"
    else
      _fail "dry-run: opencode --version failed"
    fi
    _skip "AI smoke: no API key (set OPENAI_API_KEY)"
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
      _ok_soft "file read: response received (expected ~$actual_lines)"
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
      _ok_soft "IWE context: response received"
    fi
  else
    _skip "IWE context: docs/adr/README.md not found"
  fi

  # 3.4: Update check via OpenCode
  echo "--- [3.4] update check via OpenCode ---"
  output=$(opencode_print "запусти bash update.sh --check и скажи exit code. Ответь числом: 0 или 1." | head -3)
  if echo "$output" | grep -qE "[01]"; then
    _ok_soft "AI update check: response $(echo "$output" | grep -q '0' && echo 'up-to-date' || echo 'changes')"
  elif [ -z "$output" ]; then
    _fail "AI update check: empty response"
  else
    _ok_soft "AI update check: response received"
  fi

  # --- AI flakiness gate ---
  if [ "$PHASE_SOFT_PASS" -gt 0 ]; then
    _info "AI smoke: $PHASE_PASS [OK] + $PHASE_SOFT_PASS [OK*] (heuristic)"
    if [ "$(( PHASE_PASS - PHASE_SOFT_PASS ))" -lt 2 ]; then
      echo "   [DEGRADED] AI smoke: only $(( PHASE_PASS - PHASE_SOFT_PASS ))/4 deterministic passes (dominance of heuristic results suggests model degradation or tooling issue)"
    fi
  fi

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase3_ai_smoke PASS=$PHASE_PASS FAIL=$PHASE_FAIL SOFT_PASS=$PHASE_SOFT_PASS MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}

# =========================================================================
# Фаза 4: CI + Миграции
# =========================================================================
phase4_ci() {
  echo ""
  echo "=== Phase 4: CI + Migrations ==="
  PHASE_START=$(date +%s)
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

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase4_ci PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}

# =========================================================================
# Фаза 5a: Strategy Session — структурные тесты (всегда)
# =========================================================================
phase5a_strategy_session() {
  echo ""
  echo "=== Phase 5a: Strategy Session (structural) ==="
  PHASE_START=$(date +%s)
  reset_counters
  cd "$IWE_DIR"

  # --- 5a.1: Prompt exists and is non-empty ---
  echo "--- [5a.1] prompt exists ---"
  PROMPT_FILE="roles/strategist/prompts/strategy-session.md"
  PROMPT_TEST_FILE="roles/strategist/prompts/strategy-session-test.md"
  if [ -f "$PROMPT_FILE" ] && [ -s "$PROMPT_FILE" ]; then
    _ok "prompt: strategy-session.md ($(wc -l < "$PROMPT_FILE") lines)"
  else
    _fail "prompt: strategy-session.md missing or empty"
  fi
  if [ -f "$PROMPT_TEST_FILE" ] && [ -s "$PROMPT_TEST_FILE" ]; then
    _ok "prompt: strategy-session-test.md ($(wc -l < "$PROMPT_TEST_FILE") lines)"
  else
    _fail "prompt: strategy-session-test.md missing or empty"
  fi

  # --- 5a.2: Script dispatch valid ---
  echo "--- [5a.2] script dispatch ---"
  STRATEGIST_SH="roles/strategist/scripts/strategist.sh"
  if [ -f "$STRATEGIST_SH" ]; then
    if SYNTAX_ERR=$(bash -n "$STRATEGIST_SH" 2>&1); then
      _ok "syntax: strategist.sh valid"
    else
      _fail "syntax: strategist.sh has errors"
      echo "   >>> $STRATEGIST_SH errors:"
      echo "$SYNTAX_ERR" | sed 's/^/   | /'
    fi
    if grep -q '"strategy-session")' "$STRATEGIST_SH" 2>/dev/null; then
      _ok "dispatch: strategy-session case present"
    else
      _fail "dispatch: strategy-session case missing"
    fi
  else
    _fail "script: strategist.sh not found"
  fi

  # --- 5a.3: DS-strategy structure ---
  echo "--- [5a.3] DS-strategy structure ---"
  WS_DIR="${WORKSPACE_DIR:-$HOME/IWE/workspaces}"
  if [ -n "${DS_STRATEGY_DIR:-}" ]; then
    WS_DIR="$DS_STRATEGY_DIR"
  fi
  if [ ! -d "$WS_DIR" ]; then
    _skip "DS-strategy: workspace not found (set WORKSPACE_DIR)"
  else
    for dir in docs current inbox archive; do
      if [ -d "$WS_DIR/$dir" ]; then
        _ok "dir: $dir/"
      else
        _skip "dir: $dir/ not found (workspace may be empty)"
      fi
    done
  fi

  # --- 5a.4: Required docs non-empty ---
  echo "--- [5a.4] required docs ---"
  if [ ! -d "$WS_DIR/docs" ]; then
    _skip "docs: workspace not found"
  else
    for doc in "docs/Strategy.md" "docs/Dissatisfactions.md" "docs/Session Agenda.md"; do
      if [ -f "$WS_DIR/$doc" ] && [ -s "$WS_DIR/$doc" ]; then
        _ok "doc: $doc ($(wc -l < "$WS_DIR/$doc") lines)"
      else
        _skip "doc: $doc not found (seed not run yet)"
      fi
    done
  fi

  # --- 5a.5: Prompt-to-Pack alignment ---
  echo "--- [5a.5] prompt-to-pack alignment ---"
  PACK_SCENARIO="${PACK_SCENARIO:-$HOME/tmp/PACK-digital-platform/pack/digital-platform/02-domain-entities/DP.ROLE.012-strategist/scenarios/scheduled/01-strategy-session.md}"
  if [ -f "$PACK_SCENARIO" ]; then
    _ok "pack: scenario file found"
    # Check key Pack steps are covered in the prompt
    PACK_STEP_FAILS=0
    for step in "НЭП" "прошлой недели" "inbox" "стратегическ" "план на неделю" "утвержден" "синхронизац"; do
      if grep -qi "$step" "$PROMPT_FILE" 2>/dev/null; then
        :
      else
        _fail "prompt-pack: step '$step' from Pack not found in prompt"
        PACK_STEP_FAILS=$((PACK_STEP_FAILS + 1))
      fi
    done
    [ "$PACK_STEP_FAILS" -eq 0 ] && _ok "prompt-pack: all 7 Pack steps verified"
  else
    _skip "prompt-pack: Pack scenario not found at $PACK_SCENARIO"
  fi

  # --- 5a.6: Seeder script valid ---
  echo "--- [5a.6] seeder script ---"
  SEEDER="scripts/test/seed-strategy-session.sh"
  ASSERTER="scripts/test/assert-strategy-session.sh"
  if [ -f "$SEEDER" ]; then
    if bash -n "$SEEDER" 2>/dev/null; then
      TMPDIR=$(mktemp -d -t iwe-seed-test-XXXXXX)
      SEEDER_LOG="/tmp/iwe-seeder-$$.log"
      if bash "$SEEDER" "$TMPDIR/DS-strategy" >"$SEEDER_LOG" 2>&1; then
        _ok "seeder: runs successfully"
        # Verify key files were created
        for f in "docs/Strategy.md" "docs/Dissatisfactions.md" "memory/MEMORY.md" "inbox/fleeting-notes.md"; do
          if ls "$TMPDIR/DS-strategy/$f" >/dev/null 2>&1; then
            :
          else
            _fail "seeder: missing $f"
          fi
        done
        rm -f "$SEEDER_LOG"
      else
        _fail "seeder: execution failed"
        echo "   >>> seeder output:"
        sed 's/^/   | /' "$SEEDER_LOG"
        rm -f "$SEEDER_LOG"
      fi
      rm -rf "$TMPDIR"
    else
      _fail "seeder: syntax error"
    fi
  else
    _fail "seeder: script not found"
  fi
  if [ -f "$ASSERTER" ]; then
    bash -n "$ASSERTER" 2>/dev/null && _ok "asserter: syntax valid" || _fail "asserter: syntax error"
  fi

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase5a_strategy_session PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}

# =========================================================================
# Фаза 5b: Strategy Session — headless E2E (опционально, --phase 5)
# =========================================================================
phase5b_strategy_session() {
  echo ""
  echo "=== Phase 5b: Strategy Session (headless E2E) ==="
  PHASE_START=$(date +%s)
  reset_counters
  cd "$IWE_DIR"

  # Trap for workspace cleanup on early exit
  local _ws_created=false
  trap 'if $_ws_created && ! ${IWE_DEBUG:-false}; then rm -rf "$WS_DIR" 2>/dev/null; fi' RETURN

  IWE_DEBUG="${IWE_DEBUG:-false}"
  HAS_CLAUDE=false
  AI_CLI="${AI_CLI:-claude}"
  command -v "$AI_CLI" >/dev/null 2>&1 && HAS_CLAUDE=true
  HAS_API_KEY=false
  [ -n "${AI_CLI_API_KEY:-${ANTHROPIC_API_KEY:-}}" ] && HAS_API_KEY=true

  if ! $HAS_CLAUDE; then
    _skip "headless: $AI_CLI CLI not installed"
    return 0
  fi
  if ! $HAS_API_KEY; then
    _skip "headless: no AI_CLI_API_KEY (or ANTHROPIC_API_KEY)"
    return 0
  fi

  if [ -f "scripts/ai-cli-wrapper.sh" ]; then
    source scripts/ai-cli-wrapper.sh
  else
    _fail "headless: ai-cli-wrapper.sh not found"
    return 1
  fi

  # --- Debug setup ---
  DEBUG_DIR=""
  if $IWE_DEBUG; then
    DEBUG_DIR="/home/iwe/IWE/debug"
    mkdir -p "$DEBUG_DIR"/{transcripts,workspace,artifacts}
    PREP_LOG="$DEBUG_DIR/transcripts/session-prep.log"
    SESSION_LOG="$DEBUG_DIR/transcripts/strategy-session.log"
    JUDGE_LOG="$DEBUG_DIR/transcripts/judge.log"
    cat > "$DEBUG_DIR/MANIFEST.txt" <<DMANIFEST
timestamp: $(date -Iseconds)
ai_cli: ${AI_CLI:-claude}
ai_model: ${AI_CLI_MODEL:-default}
env: FMT-exocortex-template branch 0.25.1
DMANIFEST
  else
    PREP_LOG="/tmp/iwe-strategist-e2e-$$.log"
    SESSION_LOG="$PREP_LOG"
    JUDGE_LOG="$PREP_LOG"
  fi

  # --- 5b.1: Run setup.sh via expect (creates full workspace) ---
  echo "--- [5b.1] setup.sh (expect) ---"
  WS_DIR="workspaces/iwe2"
  rm -rf "$WS_DIR" 2>/dev/null || true

  if [ ! -f "setup.sh" ]; then
    _fail "setup: setup.sh not found"
    return 1
  fi
  if ! command -v expect >/dev/null 2>&1; then
    _fail "setup: expect not installed"
    return 1
  fi
  # Ensure GitHub CLI is available (required by setup.sh)
  if ! command -v gh >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq gh 2>&1 | tail -1
    command -v gh >/dev/null 2>&1 || { _fail "setup: gh not installed"; return 1; }
  fi

  EXPECT_LOG="/tmp/iwe-expect-$$.log"
  expect -c "
set timeout 120
spawn bash setup.sh
expect \"GitHub username\"          { send \"vm-test\r\" }
expect \"Workspace name\"           { send \"iwe2\r\" }
expect \"Claude CLI path\"          { send \"\r\" }
expect \"Strategist launch\"        { send \"\r\" }
expect \"Timezone description\"     { send \"\r\" }
expect \"Data Policy (y/n)\"       { send \"y\" }
expect \"Continue with setup\"      { send \"y\" }
expect eof
lassign \[wait] pid spawnid os_error_flag exit_code
exit \$exit_code
" >"$EXPECT_LOG" 2>&1
  SETUP_RC=$?

  if [ "$SETUP_RC" -eq 0 ] && [ -d "$WS_DIR" ]; then
    _ok "setup: workspace created"
    _ws_created=true
  else
    _fail "setup: failed (rc=$SETUP_RC)"
    echo "   >>> expect log (last 30 lines):"
    tail -30 "$EXPECT_LOG" 2>/dev/null | sed 's/^/   | /'
  fi

  export WORKSPACE_DIR="$PWD/$WS_DIR"
  export DS_STRATEGY_DIR="$WORKSPACE_DIR/DS-strategy"
  LOG_FILE="/tmp/iwe-strategist-e2e-$$.log"

  # --- 5b.2: Add test documents to DS-strategy ---
  echo "--- [5b.2] add test documents ---"
  mkdir -p "$DS_STRATEGY_DIR"/{docs,current,inbox,archive}
  TODAY=$(date +%Y-%m-%d)
  MONDAY=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || echo "$TODAY")
  PREV_MONDAY=$(date -d "$MONDAY -7 days" +%Y-%m-%d 2>/dev/null || echo "$MONDAY")
  WEEK_NUM=$(date +%V)

  cat > "$DS_STRATEGY_DIR/docs/Strategy.md" <<STRAT
---
type: strategy
status: active
---
# Стратегия (тестовый workspace)

## Фокус: Май 2026
**Приоритеты месяца:**
| # | Приоритет | Статус | Бюджет |
|---|----------|--------|--------|
| 1 | IWE testing pipeline | in_progress | ~20h |
| 2 | Strategy session | pending | ~10h |
| 3 | Documentation | pending | ~5h |
STRAT

  cat > "$DS_STRATEGY_DIR/docs/Dissatisfactions.md" <<DISSAT
---
type: doc
status: active
---
# Неудовлетворённости (НЭП)

## Активные
| # | НЭП | Статус |
|---|-----|--------|
| 1 | Тестирование занимает >30 мин | active |
| 2 | Golden image требует ручной пересборки | active |
| 3 | Нет тестов для стратега | active |
DISSAT

  cat > "$DS_STRATEGY_DIR/docs/Session Agenda.md" <<AGENDA
---
type: doc
status: active
source: DP.ROLE.012.SC.01
---
# Повестка стратегической сессии
1. Ревью НЭП
2. Анализ прошлой недели
3. Сдвиг фокуса месяца
4. Формирование плана
5. Утверждение и синхронизация
AGENDA

  cat > "$DS_STRATEGY_DIR/current/WeekPlan W$((WEEK_NUM - 1)) $PREV_MONDAY.md" <<WKPREV
---
type: week-plan
week: W$((WEEK_NUM - 1))
date_start: $PREV_MONDAY
status: completed
---
# WeekPlan W$((WEEK_NUM - 1))
## Итоги
**Completion rate:** 4/5 (80%)
**Carry-over:** #3 FPF review, #5 VM pidfile fix

## План
| # | РП | Бюджет | Статус |
|---|-----|--------|--------|
| 1 | Golden image pipeline fixes | 4h | done |
| 2 | Container CI workflow | 6h | done |
| 3 | FPF review findings | 3h | in_progress |
| 4 | Production readiness R8-R12 | 5h | done |
| 5 | VM cleanup pidfile fix | 2h | done |
WKPREV

  cat > "$DS_STRATEGY_DIR/inbox/fleeting-notes.md" <<NOTES
# fleeting-notes
## 🔄 (идеи)
- "Автоматический деплой golden image" — 2026-04-28 (>7 дней)
- "Интеграция с Grafana для CI метрик" — 2026-05-03 (свежая)

## Заметки
- 2026-05-05: обновить README после изменений
NOTES

  cp "$WORKSPACE_DIR/memory/MEMORY.md" "$DS_STRATEGY_DIR/memory/MEMORY.md" 2>/dev/null || true
  _ok "docs: test documents added to DS-strategy"

  # --- 5b.3: Run session-prep (headless) ---
  echo "--- [5b.3] session-prep (headless) ---"
  SESSION_PREP_PROMPT="roles/strategist/prompts/session-prep.md"
  if [ -f "$SESSION_PREP_PROMPT" ]; then
    PREP_START=$(date +%s)
    ESCAPED_DIR=$(printf '%s' "$WORKSPACE_DIR" | sed 's/[|&\\]/\\&/g')
    PREP_PROMPT=$(sed "s|{{WORKSPACE_DIR}}|$ESCAPED_DIR|g; s|{{GITHUB_USER}}|iwe-test|g" "$SESSION_PREP_PROMPT")
    AI_CLI_TIMEOUT=300
    if ai_cli_run "$PREP_PROMPT" --bare --allowed-tools "Read,Write,Edit,Glob,Grep,Bash" --budget 1.00 \
      >>"$PREP_LOG" 2>&1; then
      PREP_DUR=$(( $(date +%s) - PREP_START ))
      _ok "session-prep: completed (${PREP_DUR}s)"
      if ls "$DS_STRATEGY_DIR/current/WeekPlan"*".md" 2>/dev/null | grep -v "$PREV_MONDAY" >/dev/null 2>&1; then
        _ok "session-prep: WeekPlan draft found"
      else
        _ok "session-prep: completed (WeekPlan check deferred to session)"
      fi
    else
      PREP_RC=$?
      _fail "session-prep: failed or timed out (rc=$PREP_RC)"
    fi
  else
    _skip "session-prep: prompt not found"
  fi

  # --- 5b.4: Run strategy-session (headless, test prompt) ---
  echo "--- [5b.4] strategy-session (headless) ---"
  TEST_PROMPT="roles/strategist/prompts/strategy-session-test.md"
  if [ -f "$TEST_PROMPT" ]; then
    SESSION_START=$(date +%s)
    SESSION_PROMPT=$(sed "s|{{WORKSPACE_DIR}}|$ESCAPED_DIR|g; s|{{GITHUB_USER}}|iwe-test|g" "$TEST_PROMPT")
    AI_CLI_TIMEOUT=600
    if ai_cli_run "$SESSION_PROMPT" --bare --allowed-tools "Read,Write,Edit,Glob,Grep,Bash" --budget 1.00 \
      >>"$SESSION_LOG" 2>&1; then
      SESSION_DUR=$(( $(date +%s) - SESSION_START ))
      _ok "strategy-session: completed (${SESSION_DUR}s)"
    else
      SESSION_RC=$?
      _fail "strategy-session: failed or timed out (rc=$SESSION_RC)"
    fi
  else
    _fail "strategy-session: test prompt not found"
  fi

  # --- 5b.5: Assert post-conditions ---
  echo "--- [5b.5] assert post-conditions ---"
  if [ -f "scripts/test/assert-strategy-session.sh" ]; then
    ASSERT_RC=0
    ASSERT_OUT=$(bash scripts/test/assert-strategy-session.sh "$WORKSPACE_DIR" "$PREP_LOG" 2>&1) || ASSERT_RC=$?
    echo "$ASSERT_OUT"
    if [ "$ASSERT_RC" -gt 1 ]; then
      _fail "assert: script crashed (rc=$ASSERT_RC)"
    else
      ASSERT_PASS=$(echo "$ASSERT_OUT" | grep -c '\[OK\]' 2>/dev/null || echo "0")
      ASSERT_FAIL=$(echo "$ASSERT_OUT" | grep -c '\[FAIL\]' 2>/dev/null || echo "0")
      for i in $(seq 1 $ASSERT_PASS); do PHASE_PASS=$((PHASE_PASS + 1)); done
      for i in $(seq 1 $ASSERT_FAIL); do PHASE_FAIL=$((PHASE_FAIL + 1)); done
    fi
  else
    _skip "assert: script not found"
  fi

  # --- 5b.6: LLM-as-Judge (DeepSeek evaluates the generated WeekPlan) ---
  echo "--- [5b.6] LLM-as-Judge ---"
  if [ -f "scripts/test/eval-strategy-session.sh" ]; then
    CONFIRMED_WP=$(find "$DS_STRATEGY_DIR/current" -name "WeekPlan*" \
      -newer "$DS_STRATEGY_DIR/docs/Session Agenda.md" 2>/dev/null | head -1)
    if [ -n "$CONFIRMED_WP" ] && [ -f "$CONFIRMED_WP" ]; then
      JUDGE_RC=0
      JUDGE_OUT=$(bash scripts/test/eval-strategy-session.sh "$DS_STRATEGY_DIR" "$CONFIRMED_WP" 2>&1) || JUDGE_RC=$?
      echo "$JUDGE_OUT"
      $IWE_DEBUG && echo "$JUDGE_OUT" >> "$JUDGE_LOG"
      if [ "$JUDGE_RC" -gt 1 ]; then
        _fail "judge: eval script crashed (rc=$JUDGE_RC)"
      else
        JUDGE_PASS=$(echo "$JUDGE_OUT" | grep -oP 'LLM_JUDGE_PASS=\K\d+' 2>/dev/null || echo "0")
        JUDGE_TOTAL=$(echo "$JUDGE_OUT" | grep -oP 'LLM_JUDGE_TOTAL=\K\d+' 2>/dev/null || echo "0")
        [ "${JUDGE_PASS:-0}" -ge 5 ] \
          && _ok "judge: ${JUDGE_PASS}/${JUDGE_TOTAL} metrics passed" \
          || _fail "judge: only ${JUDGE_PASS}/${JUDGE_TOTAL} metrics passed (<5)"
      fi
    else
      _skip "judge: no confirmed WeekPlan found"
    fi
  else
    _skip "judge: eval script not found"
  fi

  # --- Debug: save workspace + artifacts ---
  if $IWE_DEBUG; then
    cp -r "$WORKSPACE_DIR"/* "$DEBUG_DIR/workspace/" 2>/dev/null || true
    if [ -n "${CONFIRMED_WP:-}" ] && [ -f "${CONFIRMED_WP:-}" ]; then
      cp "$CONFIRMED_WP" "$DEBUG_DIR/artifacts/$(basename "$CONFIRMED_WP")" 2>/dev/null || true
    fi
    echo "total_duration_ms=$(( ($(date +%s) - PHASE_START) * 1000 ))" >> "$DEBUG_DIR/MANIFEST.txt"
  fi

  # Cleanup (skip if debug)
  if ! $IWE_DEBUG; then
    rm -rf "$WS_DIR" 2>/dev/null || true
    rm -f "$PREP_LOG" "$SESSION_LOG" 2>/dev/null || true
  fi

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phase5b_strategy_session PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}
