# IWE Testing Process — Design Document

> **Repo:** FMT-exocortex-template
> **Status:** Active
> **Last updated:** 2026-05-06
> **Related ADRs:** ADR-005 (update delivery), ADR-007 (golden image), ADR-008 (AI provider abstraction)

---

## 1. Architecture

### 1.1 Two Pipelines, One Test Library

IWE testing runs on two independent infrastructure backends (VM and Container), sharing a single test library (`test-phases.sh`).

```
┌──────────────────────────────────────────────────────────┐
│                    test-phases.sh                         │
│   Phase 1: Clean Install      Phase 4: CI + Migrations   │
│   Phase 2: Update              Phase 5a: Strategy Session │
│   Phase 3: AI Smoke            Phase 5b: Headless E2E     │
└──────────────┬────────────────────┬──────────────────────┘
               │                    │
┌──────────────▼──────────┐  ┌──────▼──────────────────────┐
│   VM Pipeline            │  │   Container Pipeline         │
│   scripts/vm/            │  │   scripts/container/         │
│                          │  │                             │
│   build-golden.sh        │  │   Containerfile             │
│   verify-golden.sh       │  │   build-container.sh        │
│   test-from-golden.sh    │  │   verify-container.sh       │
│   QEMU/KVM → SSH → exec  │  │   test-from-container.sh    │
│                          │  │   Podman → exec             │
└──────────────────────────┘  └─────────────────────────────┘
```

### 1.2 Shared Components

| Component | Path | Role |
|-----------|------|------|
| Test phases | `scripts/vm/test-phases.sh` | Library sourced by both pipelines |
| AI CLI wrapper | `scripts/ai-cli-wrapper.sh` | Provider-agnostic LLM execution |
| Assertion script | `scripts/test/assert-strategy-session.sh` | Post-condition checks for Phase 5b |
| Seed script | `scripts/test/seed-strategy-session.sh` | Test data creation for Phase 5b |

### 1.3 CI Integration

Both pipelines are triggered on push/PR to `0.25.1` and `main`, plus `workflow_dispatch` for manual runs:

| Workflow | Runner | What |
|----------|--------|------|
| `test-golden.yml` | `[self-hosted, kvm]` | VM tests via QEMU golden image |
| `test-container.yml` | `[self-hosted, podman]` | Container tests via Podman |
| `validate-template.yml` | `ubuntu-latest` | ShellCheck, static validation |

---

## 2. Running Tests

### 2.1 Local — Container (fastest, recommended for development)

```bash
# Prerequisites
sudo apt install -y podman

# Build image (once, ~5 min)
bash scripts/container/build-container.sh --version 0.25.1

# Verify image
bash scripts/container/verify-container.sh --version 0.25.1 --full

# Run all phases (structural, ~30 sec)
bash scripts/container/test-from-container.sh --version 0.25.1

# Run specific phase
bash scripts/container/test-from-container.sh --phase 1
bash scripts/container/test-from-container.sh --phase "5a"
bash scripts/container/test-from-container.sh --phase "5" --verbose   # headless E2E

# Keep container after test (debugging)
bash scripts/container/test-from-container.sh --phase 3 --keep
podman exec -it iwe-test-NNNNN bash
podman rm -f iwe-test-NNNNN
```

### 2.2 Local — VM (full environment, mirrors Golden Image)

```bash
# Prerequisites
sudo apt install -y qemu-kvm libguestfs-tools cloud-image-utils

# Create SSH key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_iwe_test -N "" -C "iwe-test"

# Build golden image (once, ~10 min)
bash scripts/vm/build-golden.sh --version 0.25.1

# Verify
bash scripts/vm/verify-golden.sh --image ~/.cache/iwe-golden/iwe-golden-0.25.1.qcow2

# Run all phases
bash scripts/vm/test-from-golden.sh --version 0.25.1

# Run specific phase + keep VM
bash scripts/vm/test-from-golden.sh --phase 1 --keep
ssh -i ~/.ssh/id_ed25519_iwe_test -p 2222 iwe@localhost
```

### 2.3 CI — GitHub Actions

```bash
# Trigger manually
gh workflow run "IWE Container Tests" --repo abcdef0101/FMT-exocortex-template --ref 0.25.1

# With headless E2E (Phase 5b, ~$1-2)
gh workflow run "IWE Container Tests" -f run_headless_e2e=true

# Trigger golden image tests
gh workflow run "IWE Golden Image Tests" --repo abcdef0101/FMT-exocortex-template --ref 0.25.1
```

### 2.4 Secrets Configuration

Create `~/.iwe-test-vm/secrets/.env`:

```bash
# Phase 3: AI Smoke (optional — phase skips without keys)
OPENAI_API_KEY="sk-..."

# Phase 5b: Headless E2E (optional — phase skips without keys)
ANTHROPIC_API_KEY="sk-ant-..."
AI_CLI_API_KEY="sk-..."

# OpenCode provider auto-detection
DEEPSEEK_API_KEY="sk-..."    # for opencode deepseek provider
AI_CLI_MODEL="deepseek/deepseek-chat"  # model for opencode (ignored by claude)

# GitHub CLI (for strategies that clone from GitHub)
GH_TOKEN="ghp_..."

# Custom provider (alternative to built-in providers)
# AI_CLI_BASE_URL="https://my-api.company.com/v1"
```

For CI, add secrets via GitHub:
```bash
gh secret set OPENAI_API_KEY --repo abcdef0101/FMT-exocortex-template --body "sk-..."
gh secret set ANTHROPIC_API_KEY --repo abcdef0101/FMT-exocortex-template --body "sk-ant-..."
gh secret set AI_CLI_API_KEY --repo abcdef0101/FMT-exocortex-template --body "sk-..."
```

---

## 3. Test Phases

### 3.1 Phase 1: Clean Install

**Purpose:** Verify `setup.sh` works from scratch.

| # | Test | What it checks | Deterministic? |
|---|------|---------------|:---:|
| 1.1 | `setup.sh --validate` | Template source files + workspace runtime validation | ✅ |
| 1.2 | `manifest apply` | `seed/manifest.yaml` applies ≥7 artifacts | ✅ |
| 1.3 | `copy-once enforcement` | User edits to `params.yaml` survive re-apply | ✅ |
| 1.4 | `workspace structure` | All 7 expected files present | ✅ |
| 1.5 | `symlink integrity` | `persistent-memory` symlink valid | ✅ |
| 1.6 | `run-phase0.sh` | Unit tests: 14 checks (checksums, semver, migrations, etc.) | ✅ |

**Exit criteria:** 8/8 [OK]. All structural + unit tests pass.

### 3.2 Phase 2: Update

**Purpose:** Verify `update.sh` update mechanism.

| # | Test | What it checks | Deterministic? |
|---|------|---------------|:---:|
| 2.1 | `update.sh --check` (no changes) | Reports up-to-date | ✅ |
| 2.2 | `update.sh --check` (mock upstream) | Detects upstream changes | ✅ |
| 2.3 | `update.sh --apply` | Applies update, `checksums.yaml` exists | ✅ |
| 2.4 | `3-way merge` | Non-conflicting merge between base/ours/theirs | ✅ |
| 2.5 | `run-e2e.sh` | E2E tests: 0 failures | ✅ |

**Exit criteria:** 5/5 [OK].

### 3.3 Phase 3: AI Smoke

**Purpose:** Verify OpenCode works in the test environment and can interact with the repo.

| # | Test | What it checks | Deterministic? |
|---|------|---------------|:---:|
| 3.0 | `opencode --version` (dry-run) | Binary works without API key | ✅ |
| 3.1 | Basic smoke | Exact match: "IWE test VM OK" | ✅ [OK] |
| 3.2 | File read | Line count of `protocol-open.md` | 🟡 [OK*] if heuristic |
| 3.3 | IWE context | ADR numbers from `docs/adr/README.md` | 🟡 [OK*] if heuristic |
| 3.4 | Update check | Runs `update.sh --check` via AI | 🟡 [OK*] if heuristic |

**Skip conditions:** `OPENAI_API_KEY` not set → skip entire phase. `opencode` not installed → skip (should have been caught by verify).

**Degradation gate:** If <2 tests produce deterministic `[OK]` (not `[OK*]`), a `[DEGRADED]` warning is printed. This does not fail the phase but flags potential model degradation.

**Exit criteria:** 4/4 tests pass (some may be [OK*]).

### 3.4 Phase 4: CI + Migrations

**Purpose:** Verify CI enforcement and migration framework.

| # | Test | What it checks | Deterministic? |
|---|------|---------------|:---:|
| 4.1 | `enforce-semver.sh` | Semantic versioning enforced | ✅ |
| 4.2 | `run-migrations.sh` | Migrations run from "0.0.0" to "99.99.99" | ✅ |
| 4.3 | `checksums integrity` | `checksums.yaml` has >100 entries | ✅ |
| 4.4 | NEVER-TOUCH final | User edits in `params.yaml` survive all 4 phases | ✅ |

**Exit criteria:** 4/4 [OK].

### 3.5 Phase 5a: Strategy Session (Structural)

**Purpose:** Verify strategy-session infrastructure is correctly wired. No LLM calls.

| # | Test | What it checks | Deterministic? |
|---|------|---------------|:---:|
| 5a.1 | Prompt exists | `strategy-session.md` + `strategy-session-test.md` non-empty | ✅ |
| 5a.2 | Script dispatch | `strategist.sh` syntax valid, `strategy-session` case present | ✅ |
| 5a.3 | DS-strategy structure | `docs/`, `current/`, `inbox/`, `archive/` directories exist | ✅ |
| 5a.4 | Required docs | `Strategy.md`, `Dissatisfactions.md`, `Session Agenda.md` non-empty | ✅ |
| 5a.5 | Prompt-to-Pack alignment | Key Pack scenario steps found in prompt | ✅ |
| 5a.6 | Seeder + asserter | Both scripts syntax-valid, seeder runs successfully | ✅ |

**Exit criteria:** 6/6 [OK]. Runs in `all` mode. $0 cost.

### 3.6 Phase 5b: Strategy Session (Headless E2E)

**Purpose:** Run actual strategy session via LLM in headless mode. **NOT in `all`** — runs only via `--phase 5` or `workflow_dispatch`.

| # | Test | What it checks | Cost |
|---|------|---------------|:---:|
| 5b.1 | Seed test data | Creates mock DS-strategy with WeekPlan, NEP, Memory | $0 |
| 5b.2 | Session-prep | `claude --bare -p session-prep.md` → WeekPlan draft created | ~$0.50 |
| 5b.3 | Strategy-session | `claude --bare -p strategy-session-test.md` → WeekPlan confirmed | ~$0.50 |
| 5b.4 | Assert post-conditions | Structural checks (see §3.6.1) | $0 |

**Skip conditions:** `ANTHROPIC_API_KEY` (or `AI_CLI_API_KEY`) not set → skip.

**AI provider flow:**
```
detect_ai_cli()
  ├── AI_CLI=claude (default) → claude --bare -p
  │     ├── success → done
  │     └── failure (Not logged in) → fallback to opencode
  └── AI_CLI=opencode → opencode run -m AI_CLI_MODEL
```

#### 3.6.1 Post-condition Assertions

| # | Check | Type | Threshold |
|---|-------|------|-----------|
| 1 | WeekPlan created + `status: confirmed` | Structural | Must exist |
| 2 | Sections: "Итоги", "План на неделю", "Повестка" | Content | All 3 present |
| 3 | File size > 500 bytes | Content | Guards empty files |
| 4 | Table rows: ≥1 РП entry | Content | `grep -c '^\| #'` |
| 5 | Frontmatter: `type:`, `week:`, `date_start:`, `status:`, `agent:` | Content | All 5 present |
| 6 | Carry-over: ≥1 past РП reference found | Content | `grep -i` on known seed identifiers |
| 7 | MEMORY.md: "РП текущей недели" section present | Content | Section exists |
| 8 | No ERROR in strategist log | Signal | `grep -qi "ERROR"` must be empty |
| 9 | Inbox processed | Structural | Old notes cleaned |

---

## 4. Adding a New Test Phase

### 4.1 Checklist (5 files)

| # | File | Change |
|---|------|--------|
| 1 | `scripts/vm/test-phases.sh` | Add function `phaseN_xxx()` following the standard skeleton (see §4.2) |
| 2 | `scripts/container/test-from-container.sh` | Add `N) run_phase N "Title" "phaseN_xxx" ;;` + in `all)` branch |
| 3 | `scripts/vm/test-from-golden.sh` | Same dispatch change |
| 4 | `.github/workflows/test-container.yml` | Update `test_phase` description to include new phase number |
| 5 | `.github/workflows/test-golden.yml` | Same description update |

### 4.2 Phase Function Skeleton

```bash
# =========================================================================
# Фаза N: <Human-readable title>
# =========================================================================
phaseN_purpose() {
  echo ""
  echo "=== Phase N: <Title> ==="
  PHASE_START=$(date +%s)
  reset_counters
  cd "$IWE_DIR"

  # --- [N.1] test label ---
  echo "--- [N.1] test label ---"
  if <condition>; then
    _ok "test: passed"
  else
    _fail "test: failed"
  fi

  # --- [N.2] next test ---
  # ...

  PHASE_DURATION=$(( $(date +%s) - PHASE_START ))
  echo "phaseN_purpose PASS=$PHASE_PASS FAIL=$PHASE_FAIL MS=$(( PHASE_DURATION * 1000 ))" >> "$METRICS_FILE"
}
```

### 4.3 Helper Functions

| Function | Usage | Effect |
|----------|-------|--------|
| `_ok "message"` | Deterministic pass | `PHASE_PASS++`, prints `[OK]` |
| `_ok_soft "message"` | Heuristic pass (AI responses) | `PHASE_PASS++`, `PHASE_SOFT_PASS++`, prints `[OK*]` |
| `_fail "message"` | Test failure | `PHASE_FAIL++`, prints `[FAIL]` |
| `_skip "message"` | Optional test skipped | No counter change, prints `[SKIP]` |
| `_info "message"` | Informational | No counter change, prints `[INFO]` |
| `reset_counters` | Reset all counters to 0 | Called at phase start |
| `ai_cli_run "prompt" --bare --allowed-tools "..."` | Run AI CLI via wrapper | Sources `ai-cli-wrapper.sh` |

---

## 5. AI Provider Configuration

### 5.1 Provider Selection

The system auto-detects the available AI CLI:

```bash
# Priority order:
1. $AI_CLI env var (explicit choice)
2. claude  (if in PATH)
3. opencode (if in PATH)
4. claude  (fallback, will error)
```

### 5.2 Environment Variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `AI_CLI` | wrapper | Override auto-detection: `claude` or `opencode` |
| `AI_CLI_API_KEY` | wrapper | Provider-agnostic API key (fallback: `ANTHROPIC_API_KEY`) |
| `AI_CLI_MODEL` | opencode | Model in `provider/model` format (e.g., `deepseek/deepseek-chat`) |
| `AI_CLI_BASE_URL` | opencode | Custom API endpoint |
| `AI_CLI_TIMEOUT` | wrapper | Timeout in seconds (default: 300 for tests, 1800 for strategist) |
| `AI_CLI_PACKAGE` | Containerfile | npm package for installation |
| `ANTHROPIC_API_KEY` | claude | Legacy — use `AI_CLI_API_KEY` instead |
| `OPENAI_API_KEY` | Phase 3 | OpenCode AI smoke test |

### 5.3 Switching Providers

```bash
# Claude Code (default, requires Anthropic subscription)
export AI_CLI=claude
export AI_CLI_API_KEY="$ANTHROPIC_API_KEY"

# OpenCode with DeepSeek (via OpenAI-compatible endpoint)
export AI_CLI=opencode
export AI_CLI_MODEL="deepseek/deepseek-chat"
export AI_CLI_API_KEY="$DEEPSEEK_API_KEY"

# OpenCode with custom endpoint
export AI_CLI=opencode
export AI_CLI_MODEL="custom/my-model"
export AI_CLI_BASE_URL="https://my-api.company.com/v1"
export AI_CLI_API_KEY="sk-..."
```

---

## 6. Troubleshooting

### 6.1 Common Failures

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Phase 3: `[SKIP] opencode: no API key` | `OPENAI_API_KEY` not in `.env` | Add to `~/.iwe-test-vm/secrets/.env` |
| Phase 5b: `[SKIP] headless: no AI_CLI_API_KEY` | No API key configured | Add `ANTHROPIC_API_KEY` or `AI_CLI_API_KEY` to `.env` |
| Phase 5b: `[FAIL] ERROR found in strategist log` | Claude/prompts tried to access non-existent paths | Check `WORKSPACE_DIR` + `sed` substitution in prompt |
| `ProviderModelNotFoundError` | Model name missing provider prefix or provider not configured | Use `provider/model` format; add API key for the provider |
| `Not logged in · Please run /login` | Claude CLI needs auth | Set `ANTHROPIC_API_KEY` env var (--bare uses API key auth) |
| QEMU processes left after VM test | `-daemonize` double-fork bypassed `$!` | Fixed in `d723302` — uses `-pidfile` |
| Container not removed after test | Interrupted script | Run `podman rm -f iwe-test-*` |
| `[DEGRADED]` in Phase 3 | <2 deterministic AI responses | Check model output quality; may indicate prompt/model degradation |

### 6.2 Log Locations

| Context | Path |
|---------|------|
| Container test report | `scripts/container/results/container-test-YYYYMMDD-HHMMSS.txt` |
| Container phase log | `scripts/container/results/phase-N-YYYYMMDD-HHMMSS.log` |
| Container phase stderr | `scripts/container/results/phase-N-stderr-YYYYMMDD-HHMMSS.log` |
| Container metrics | `scripts/container/results/metrics-YYYYMMDD-HHMMSS.txt` |
| VM test report | `scripts/vm/results/golden-test-YYYYMMDD-HHMMSS.txt` |
| VM phase stderr | `scripts/vm/results/phase-N-stderr-YYYYMMDD-HHMMSS.log` |
| Golden image | `~/.cache/iwe-golden/iwe-golden-0.25.1.qcow2` |
| Container image | `~/.cache/iwe-container/iwe-test-0.25.1.id` |

### 6.3 Diagnostic Commands

```bash
# Check AI CLI availability in container
podman run --rm iwe-test:0.25.1 bash -lc 'command -v claude; command -v opencode; opencode providers list'

# Run single assertion manually
bash scripts/test/seed-strategy-session.sh /tmp/test-ds
bash scripts/test/assert-strategy-session.sh /tmp/test-ds/DS-strategy

# Check wrapper provider detection
source scripts/ai-cli-wrapper.sh
detect_ai_cli

# Check opencode model availability
AI_CLI=opencode opencode models 2>/dev/null | head -20
```

---

## 7. Metrics Collected

Each phase writes to `$METRICS_FILE` (`/tmp/iwe-phase-metrics.txt` inside test environment):

```
phase1_setup PASS=8 FAIL=0 MS=11000
phase2_update PASS=5 FAIL=0 MS=7000
phase3_ai_smoke PASS=4 FAIL=0 SOFT_PASS=3 MS=43000
phase4_ci PASS=4 FAIL=0 MS=0
phase5a_strategy_session PASS=6 FAIL=0 MS=500
phase5b_strategy_session PASS=8 FAIL=1 MS=178000
```

Fields: `PASS` (deterministic), `FAIL`, `SOFT_PASS` (heuristic, Phase 3 only), `MS` (milliseconds).

Metrics are archived as CI artifacts alongside test reports.

---

## 8. Production Readiness

Current score: **97%** (see ADR-007, ADR-008 for evolution).

| Dimension | Status | Details |
|-----------|:---:|---------|
| Ephemeral environments | ✅ | COW clone (VM) + `podman rm -f` (container) |
| Deterministic tests | ✅ | Phases 1, 2, 4, 5a |
| Non-deterministic flagged | ✅ | `[OK*]` + `[DEGRADED]` gate |
| Security scanning | ✅ | Trivy fs + image (non-blocking) |
| Alerting | ✅ | Slack webhook on CI failure |
| Code ownership | ✅ | `.github/CODEOWNERS` |
| Metrics | ✅ | Phase timing + pass/fail counts |
| Flakiness tracking | ✅ | `SOFT_PASS` in metrics artifact |
| Idempotent builds | ✅ | `build-*.sh` skip if exists |
| Auto-cleanup | ✅ | `trap EXIT` in all runners |
| Test isolation | ✅ | `--phase N` for individual phases |
| Artifact archiving | ✅ | CI upload-artifact |

Remaining 3%: inherent limitations of LLM non-determinism in AI smoke tests.

---

## 9. References

| Document | What |
|----------|------|
| `docs/adr/ADR-007-golden-image-testing.md` | Golden image build pipeline decision |
| `docs/adr/ADR-008-ai-provider-abstraction.md` | Multi-provider CLI support |
| `docs/adr/impl/ADR-007-implementation-plan.md` | Golden image implementation plan |
| `docs/adr/impl/ADR-008-implementation-plan.md` | AI provider abstraction plan |
| `scripts/vm/README.md` | VM-specific testing details |
| `scripts/container/Containerfile` | Container image definition |
| `docs/SETUP-GUIDE.md` | User-facing setup instructions |
| `.github/workflows/test-golden.yml` | VM CI workflow |
| `.github/workflows/test-container.yml` | Container CI workflow |
