# Remediation Plan: IWE Testing System Audit

> **Audit:** [audit-2026-05-06-testing-system.md](reports/audit-2026-05-06-testing-system.md)
> **Date:** 2026-05-06
> **Target:** 40 findings → 94% production readiness
> **Estimated effort:** ~2 hours, ~80 lines across 6 files

---

## Phase 1: CRITICAL (4 findings, ~15 min)

### C3 — Undefined `$LOG_FILE` causes unconditional Claude→OpenCode fallback

**File:** `scripts/ai-cli-wrapper.sh:89-99` | **Effort:** 1 line

**Current:**
```bash
timeout "$timeout_val" claude $flags -p "$prompt"
local claude_rc=$?
if [ $claude_rc -ne 0 ] || { grep -q "Not logged in" "$LOG_FILE" 2>/dev/null; }; then
```

**Fix:**
```bash
timeout "$timeout_val" claude $flags -p "$prompt"
local claude_rc=$?
if [ $claude_rc -ne 0 ]; then
```

**Why:** `$LOG_FILE` is never defined — expands to empty. `grep` on empty path always fails → `||` triggers → fallback runs on EVERY claude call.

---

### C4 — `--allowedTools` flag receives literal quote characters

**File:** `scripts/ai-cli-wrapper.sh:53` | **Effort:** 1 line

**Current:**
```bash
[ -n "$tools" ] && flags="$flags --allowedTools \"$tools\""
```

**Fix:**
```bash
[ -n "$tools" ] && flags="$flags --allowedTools $tools"
```

**Why:** Embedded `"` become part of the argument after word-splitting. Claude receives `--allowedTools "Read,Write"` (with quote chars), not `--allowedTools Read,Write`.

---

### C1 — Command injection via `IWE_REPO_URL`/`IWE_BRANCH` (container)

**File:** `scripts/container/test-from-container.sh:139` | **Effort:** 3 lines

**Current:**
```bash
podman exec "$CONTAINER_NAME" bash -c \
  "rm -rf ~/IWE/FMT-exocortex-template && git clone --branch $REPO_BRANCH $REPO_URL ~/IWE/FMT-exocortex-template"
```

**Fix:**
```bash
podman exec -e REPO_BRANCH -e REPO_URL "$CONTAINER_NAME" bash -c \
  'rm -rf ~/IWE/FMT-exocortex-template && git clone --branch "$REPO_BRANCH" "$REPO_URL" ~/IWE/FMT-exocortex-template'
```

**Why:** Pass variables through `-e` instead of interpolating into command string.

---

### C2 — Command injection via `IWE_REPO_URL`/`IWE_BRANCH` (VM)

**File:** `scripts/vm/test-from-golden.sh:273` | **Effort:** 1 line

**Current:**
```bash
ssh $SSH_OPTS iwe@localhost "git clone --branch $REPO_BRANCH $REPO_URL ~/IWE/FMT-exocortex-template"
```

**Fix:**
```bash
REPO_URL_ESC=$(printf '%q' "$REPO_URL")
REPO_BRANCH_ESC=$(printf '%q' "$REPO_BRANCH")
ssh $SSH_OPTS iwe@localhost "git clone --branch $REPO_BRANCH_ESC $REPO_URL_ESC ~/IWE/FMT-exocortex-template"
```

**Why:** `printf '%q'` escapes special characters for safe SSH interpolation.

---

## Phase 2: HIGH (5 findings, ~15 min)

### H1 — No `pipefail` in remote `bash -c` execution context

**File:** `test-from-container.sh:213`, `test-from-golden.sh:311` | **Effort:** 2 lines

**Current (container):**
```bash
podman exec "$CONTAINER_NAME" \
    bash -c "$SECRETS_PREAMBLE ... source ~/test-phases.sh && $func" \
    >"$PHASE_LOG" 2>"$PHASE_STDERR" || PHASE_RC=$?
```

**Fix (container):**
```bash
podman exec "$CONTAINER_NAME" \
    bash -c "set -euo pipefail; $SECRETS_PREAMBLE ... source ~/test-phases.sh && $func" \
    >"$PHASE_LOG" 2>"$PHASE_STDERR" || PHASE_RC=$?
```

**Fix (VM):**
```bash
ssh $SSH_OPTS iwe@localhost "set -euo pipefail; $SECRETS_PREAMBLE ... source ~/test-phases.sh && $func" 2>"$PHASE_STDERR" || PHASE_RC=$?
```

⚠️ **Risk:** May expose previously-masked pipeline failures. Run full test suite after applying.

---

### H2/H3 — `|| true` swallows assertion/judge crash errors

**File:** `test-phases.sh:730` (assertion), `746` (judge) | **Effort:** 10 lines

**Current (assertion):**
```bash
ASSERT_OUT=$(bash scripts/test/assert-strategy-session.sh "$WORKSPACE_DIR" "$PREP_LOG" 2>&1) || true
```

**Fix (assertion):**
```bash
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
```

**Fix (judge):**
```bash
JUDGE_RC=0
JUDGE_OUT=$(bash scripts/test/eval-strategy-session.sh "$DS_STRATEGY_DIR" "$CONFIRMED_WP" 2>&1) || JUDGE_RC=$?
echo "$JUDGE_OUT"
if [ "$JUDGE_RC" -gt 1 ]; then
    _fail "judge: eval script crashed (rc=$JUDGE_RC)"
else
    JUDGE_PASS=$(echo "$JUDGE_OUT" | grep -oP 'LLM_JUDGE_PASS=\K\d+' 2>/dev/null || echo "0")
    JUDGE_TOTAL=$(echo "$JUDGE_OUT" | grep -oP 'LLM_JUDGE_TOTAL=\K\d+' 2>/dev/null || echo "0")
    [ "${JUDGE_PASS:-0}" -ge 5 ] \
        && _ok "judge: ${JUDGE_PASS}/${JUDGE_TOTAL} metrics passed" \
        || _fail "judge: only ${JUDGE_PASS}/${JUDGE_TOTAL} metrics passed (<5)"
fi
```

**Why:** rc=2 from `assert-strategy-session.sh` means "script crashed" (shebang error, missing dependency). This is different from rc=1 ("assertions failed"). We need to distinguish.

---

### H4/H5 — Unchecked `qemu-img create` and QEMU launch

**File:** `test-from-golden.sh:158` (`qemu-img`), `177` (`QEMU`) | **Effort:** 4 lines

**Current (qemu-img):**
```bash
qemu-img create -f qcow2 -b "$GOLDEN_IMAGE" -F qcow2 "$TEST_IMAGE" 20G >/dev/null 2>&1
```

**Fix:**
```bash
if ! qemu-img create -f qcow2 -b "$GOLDEN_IMAGE" -F qcow2 "$TEST_IMAGE" 20G >/dev/null 2>&1; then
    echo "ERROR: qemu-img create failed (rc=$?)" >&2
    exit 1
fi
echo "  ✓ Created ephemeral image (${ELAPSED}s)"
```

**Current (QEMU — missing PID file check):**
```bash
# PID file read happens at lines 184-189 but never validated
```

**Fix:** Add validation after the PID file read loop:
```bash
if [ -z "${VM_PID:-}" ]; then
    echo "ERROR: QEMU failed to start (no PID file after 5s)" >&2
    exit 1
fi
```

---

## Phase 3: MEDIUM (11 findings, ~45 min)

### M1 — `grep -q && _ok` without `|| _fail`

**File:** `test-phases.sh:56-57` | **Effort:** 2 lines

```bash
# Current:
echo "$output" | grep -q "Template source files" && _ok "validate: template section"
echo "$output" | grep -q "Workspace runtime" && _ok "validate: workspace section" || true

# Fix:
echo "$output" | grep -q "Template source files" && _ok "validate: template section" \
  || _fail "validate: template section missing"
echo "$output" | grep -q "Workspace runtime" && _ok "validate: workspace section" \
  || _fail "validate: workspace section missing"
```

### M2 — Unchecked `apply_manifest` in copy-once test

**File:** `test-phases.sh:83` | **Effort:** 6 lines

Replace bare `apply_manifest ... >/dev/null 2>&1` with wrapped `if apply_manifest ...; then ... else _fail ...`.

### M3 — Any non-zero exit from `update.sh --check` becomes `_ok`

**File:** `test-phases.sh:148-154` | **Effort:** 5 lines

Add `elif [ "$rc" -eq 1 ]` before the else, make else → `_fail`.

### M4 — Unconditional `_ok` after loop of `_fail` calls

**File:** `test-phases.sh:457` | **Effort:** 3 lines

Add `PACK_STEP_FAILS` counter in the `for` loop, guard the final `_ok` with `[ "$PACK_STEP_FAILS" -eq 0 ]`.

### M5 — Sed injection via `WORKSPACE_DIR`

**File:** `test-phases.sh:689,713` | **Effort:** 2 lines

```bash
ESCAPED_DIR=$(printf '%s' "$WORKSPACE_DIR" | sed 's/[|&\\]/\\&/g')
PREP_PROMPT=$(sed "s|{{WORKSPACE_DIR}}|$ESCAPED_DIR|g; ..." "$SESSION_PREP_PROMPT")
```

### M6 — `expect setup.sh` output to `/dev/null`

**File:** `test-phases.sh:569-582` | **Effort:** 4 lines

```bash
EXPECT_LOG="/tmp/iwe-expect-$$.log"
expect -c "..." >"$EXPECT_LOG" 2>&1
SETUP_RC=$?
if [ "$SETUP_RC" -ne 0 ]; then
    _fail "setup: failed (rc=$SETUP_RC)"
    echo "   >>> expect log:"; tail -30 "$EXPECT_LOG" | sed 's/^/   | /'
fi
```

### M7 — Path mismatch: `memory/` level

**File:** `assert-strategy-session.sh:25` vs `test-phases.sh:593` | **Effort:** 2 lines

Assertion reads `$DS_DIR/memory/` but Phase 5b passes `$WORKSPACE_DIR` (has memory at workspace level). Fix: pass `$DS_STRATEGY_DIR` to assertion (memory path is `$DS_DIR/memory/` = `DS-strategy/memory/` — but the real memory is at workspace level). Resolution: assertion already corrected in latest code; verify consistency.

### M8 — No `trap` for workspace cleanup

**File:** `test-phases.sh:772` | **Effort:** 3 lines

```bash
phase5b_strategy_session() {
    local _ws_created=false
    trap '$_ws_created && ! $IWE_DEBUG && rm -rf "$WS_DIR" 2>/dev/null' RETURN
    ...
    _ws_created=true  # after successful setup.sh
```

### M9 — `podman images || true` masks daemon crash

**File:** `test-from-container.sh:83` | **Effort:** 5 lines

Check podman exit code separately: `if ! podman images ... >/tmp/podman-err; then echo "podman error"; fi`.

### M10 — `ai_cli_run` failure hidden in eval

**File:** `eval-strategy-session.sh:77` | **Effort:** 6 lines

```bash
JUDGE_RC=0
JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
if [ "$JUDGE_RC" -ne 0 ]; then
    echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; exit 2
fi
```

### M11 — YAML structural error: two `run:` keys in CI

**File:** `test-container.yml:72-97` | **Effort:** 8 lines (split into 2 steps)

```yaml
- name: Create AI CLI agent
  run: |
    echo "=== Agent setup ==="
    if command -v opencode >/dev/null 2>&1; then
      source scripts/ai-cli-wrapper.sh
      ai_cli_agent_create strategist-test "Read,Write,Edit,Glob,Grep,Bash"
    else
      echo "  opencode not found — skipping agent creation"
    fi

- name: Run tests
  id: tests
  continue-on-error: true
  env:
    IWE_BRANCH: ${{ steps.branch.outputs.branch }}
    ...
  run: |
    PHASE="${{ inputs.test_phase || 'all' }}"
    ...
```

---

## Phase 4: LOW — Priority Picks (6 findings, ~30 min)

| # | File | Fix |
|---|------|-----|
| L1 | `test-phases.sh:9,12` | Add `|| echo "WARN" >&2` to `git config` |
| L5 | `test-phases.sh:398` | Capture `bash -n` stderr, show on failure |
| L6 | `test-phases.sh:469` | Redirect seeder to log file, show on failure |
| L8 | `test-phases.sh:772` | Add `[ -n "$WS_DIR" ] &&` safety guard |
| L14 | Both runners | Show non-empty stderr always with `[INFO]` prefix |
| L20 | CI YAML | Use `printf '{"text": "%s\n%s"}'` for JSON |

### Remaining LOW (14 findings, ~45 min)

| # | File | Fix |
|---|------|-----|
| L2 | `test-phases.sh:69` | `export WORKSPACE_FULL_PATH="$WS"` — standard form |
| L3 | `test-phases.sh:97` | Save `PHASE_FAIL` before workspace loop or use local counter |
| L4 | `test-phases.sh:293` | `printf '%s'` instead of `echo` for AI output piping |
| L7 | `test-phases.sh:565` | Check passwordless sudo before `sudo apt-get` |
| L9 | `test-phases.sh:158,468` | `mktemp -d /tmp/iwe-XXXXXX` — portable across Linux/BSD |
| L10 | `test-from-golden.sh:170` | TOCTOU: let QEMU pick port, parse from output |
| L11 | `test-from-golden.sh:118` | Check `ssh-keygen` exit code |
| L12 | `test-from-golden.sh:184` | Single atomic PID file read |
| L13 | `test-from-golden.sh:283` | Add GIT_LOG to cleanup trap |
| L15 | `test-from-container.sh:253` | Check podman cp exit code separately from file existence |
| L16 | Both `test-from-*.sh` | Use `yq` or `python3 -c "import yaml"` for MANIFEST version |
| L17 | `ai-cli-wrapper.sh:111` | **False positive** — `$model` quoted in `[[ ]]`, safe. Document as intentional |
| L18 | `ai-cli-wrapper.sh:136` | Backup `opencode.json` before overwrite |
| L19 | `test-container.yml:37` | `rm -f /tmp/trivy*` at end of security scan |

---

## Execution Order

```
C3 → C4 → C1 → C2 → H1 → H2 → H3 → H4 → H5 → M11 → M1-M6 → M8-M10 → L1,L5,L6,L8,L14,L20 → L2-L4,L7,L9-L13,L15-L19
```

After each phase:
- `bash -n *.sh` on all modified files
- `bash scripts/container/test-from-container.sh --phase 5a` (quick smoke test)

---

## PR Gain Summary

| Phase | Findings | Effort | PR Gain |
|-------|:---:|:---:|:---:|
| 1: CRITICAL | 4 | 6 lines | 81% → 88% |
| 2: HIGH | 5 | 15 lines | 88% → 92% |
| 3: MEDIUM | 11 | 40 lines | 92% → 94% |
| 4: LOW | **20** | 35 lines | 94% → 94% |
| **Total** | **40** | **~96 lines** | 81% → **94%** |

Remaining 6%: systemic changes (observability, shadow eval, regression dataset) — require separate ADRs.

---

*Plan created: 2026-05-06. Updated: 2026-05-06 (all 40 findings). Based on audit-2026-05-06-testing-system.md.*
