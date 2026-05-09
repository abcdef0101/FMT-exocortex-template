# Testing — Complete Guide

> Created: 2026-05-08
> For: New developers, AI agents, onboarding
> Covers: All test types, how to run them, directory structure, conventions

---

## Quick Start

```bash
# All unit tests (47, ~3 sec, deterministic, no secrets needed)
bash scripts/test/run-phase0.sh

# All E2E tests with AI (14 workflows, ~5 min, REQUIRES secrets)
source ~/.iwe-test-vm/secrets/.env                    # ← MUST run first
bash scripts/test/e2e/run-e2e-ai.sh all

# All E2E tests WITHOUT AI (seed + assert only, ~10 sec, no secrets)
bash scripts/test/e2e/run-e2e-ai.sh all    # works but --run phases will fail
# Better: run individual structural phases
for phase in quick-close wp-new day-close week-close; do
  bash scripts/test/e2e/run-e2e-ai.sh "$phase"
done

# All container tests (full CI suite, requires Podman)
bash scripts/container/test-from-container.sh --phase all
```

---

## Test Categories

### 1. Unit Tests — `scripts/test/test-*.sh`

**47 tests**, ~3 seconds, deterministic, 0 cost. Bash-only.

Run with:
```bash
bash scripts/test/run-phase0.sh          # all 47
bash scripts/test/run-phase0.sh --verbose  # full output
bash scripts/test/test-memory-limits.sh  # single test
```

| Phase | Count | What they test | Examples |
|-------|:-----:|----------------|----------|
| **Phase 1** — Structural & Config | 9 | Memory limits, metadata, skill manifests, roles, params, ADR, WP Context, day-rhythm, navigation | `test-memory-limits.sh`, `test-navigation-links.sh` |
| **Phase 2** — Protocols & Gates | 7 | Fallback chain, protocol-open/work/close, WP Gate, ArchGate, IntegrationGate | `test-protocol-open.sh`, `test-archgate-rubric.sh` |
| **Pre-existing** — Core | 8 | Manifest files, checksums, setup, update, template-sync, enforce-semver, extensions, migrations | `test-manifest-parser.sh`, `test-checksums.sh` |
| **Pre-existing** — AI | 3 | ai-cli-wrapper (19 tests), hooks (42), e2e-lib (20) | `test-ai-cli-wrapper.sh`, `test-hooks.sh`, `test-e2e-lib.sh` |
| **Role R1** — Install & Timers | 4 | 5 install.sh, 4 launchd plist, 8 systemd service/timer, pairing consistency | `test-role-install-scripts.sh`, `test-role-systemd-syntax.sh` |
| **Role R2** — Behavioral | 4 | strategist scenarios, 7 synchronizer scripts, extractor/verifier/auditor, 21 prompt files | `test-role-strategist.sh`, `test-role-prompt-coverage.sh` |
| **Infrastructure** — Phase 4 | 5 | strategist install, MCP JSON, Telegram notify, CI schedule, hard distinctions | `test-ci-schedule.sh`, `test-mcp-json-schema.sh` |
| **Project coverage** | 2 | Memory limits, nav links verification | `test-project-coverage.sh` (moved to skill) |

### 2. Assert Scripts — `scripts/test/assert-*.sh`

**15 scripts**, deterministic, 0 cost. Check structural invariants AFTER an AI process completes.

Run standalone:
```bash
bash scripts/test/assert-day-close.sh <workspace_dir>
bash scripts/test/assert-wp-gate.sh <workspace_dir>
```

| Script | What it validates |
|--------|-------------------|
| `assert-day-close.sh` | DayPlan: итоги дня table, multiplier, praise, commit |
| `assert-week-close.sh` | WeekPlan: итоги W{N}, completion rate, content plan |
| `assert-quick-close.sh` | Session: WP Context updated, MEMORY synced, no Day Close drift |
| `assert-wp-new.sh` | wp-new: 5-location atomic write, naming, unique number |
| `assert-day-open.sh` | DayPlan: table, calendar, carry-over, self-dev, priority markers |
| `assert-strategy-session.sh` | WeekPlan: structure, budget, carry-over, MEMORY sync |
| `assert-session-prep.sh` | Session Prep: draft WeekPlan, archive, inbox, MEMORY |
| `assert-note-review.sh` | Note Review: fleeting-notes processed, categories, archive |
| `assert-archgate.sh` | ArchGate: 7 characteristics, veto rules, modernity checks |
| `assert-integration-gate.sh` | IntegrationGate: 4-step order, P10 penalty, exceptions |
| `assert-wp-gate.sh` | WP Gate: task not in plan, workspace integrity, no new WP |
| `assert-orz-cycle.sh` | ORZ: session log, WP context, captures, MEMORY sync |
| `assert-role-execution.sh` | Role: DayPlan created, table, carry-over, self-dev |
| `assert-skill-invocation.sh` | Skill: violations detected, standard rules, imports |
| `assert-capture-to-pack.sh` | KE routing: CLAUDE.md, Pack, memory/, drafts |

### 3. E2E AI Tests — `scripts/test/seed-*.sh` + `eval-*.sh` + `rubrics-*.yaml`

**14 E2E workflows**, each = seed + eval + assert + rubrics. Requires AI CLI (`opencode` or `claude`).

Run with:
```bash
# Single workflow
bash scripts/test/e2e/run-e2e-ai.sh day-close
bash scripts/test/e2e/run-e2e-ai.sh wp-gate

# All 14 (seed → run → assert → judge)
bash scripts/test/e2e/run-e2e-ai.sh all
```

| # | Workflow | Mode | Budget | What happens |
|---|----------|:----:|:------:|--------------|
| 1 | Day Close | --run | $0.50 | AI adds итоги дня, multiplier, praise → commits |
| 2 | Week Close | --run | $0.50 | AI adds итоги W{N}, completion rate, content plan |
| 3 | Quick Close | --run | $0.20 | AI updates WP Context, MEMORY, commits |
| 4 | wp-new | --run | $0.25 | AI writes new WP to 5 locations atomically |
| 5 | Day Open | --run | $0.50 | AI builds DayPlan from WeekPlan+MEMORY+notes |
| 6 | Strategy Session | --run | $0.50 | AI builds WeekPlan from strategy+inbox |
| 7 | Session Prep | --run | $0.50 | AI archives old, creates draft WeekPlan |
| 8 | WP Gate | --run | $0.20 | AI checks plan → "add MCP" not in plan → STOP |
| 9 | ORZ Full Cycle | --run | $0.50 | AI does full Open→Work→Close cycle |
| 10 | Note Review | --run | $0.30 | AI classifies fleeting-notes into 7 categories |
| 11 | ArchGate | --run | $0.50 | AI evaluates architectural decision against ЭМОГССБ |
| 12 | IntegrationGate | --run | $0.50 | AI enforces 1→2→3→4 order for new tools |
| 13 | Role Execution | --run | $0.50 | AI runs strategist morning → produces DayPlan |
| 14 | Skill Invocation | --run | $0.50 | AI invokes /verify pack-entity → detects violations |

**E2E test anatomy (4 files each):**
```
seed-<name>.sh          → creates workspace with test data (bash only)
eval-<name>.sh          → runs AI process (--run) + LLM judge (--judge)
rubrics-<name>.yaml     → 8 scoring criteria with thresholds (0.5-0.8)
assert-<name>.sh        → structural invariant checks (deterministic)
```

### Important: running `all` — what to expect

**Prerequisites:**
```bash
# REQUIRED before running 'all':
source ~/.iwe-test-vm/secrets/.env    # AI_CLI_API_KEY + AI_CLI_MODEL
# REQUIRED in PATH:
command -v opencode || command -v claude
```

**Runtime:** ~5 minutes for all 14 workflows. Each `--run` test: 30-120 sec.

**Cost:** ~$0.06 total (DeepSeek chat, token-based). Budget caps are set per-test ($0.20-0.50) but actual spend is far lower.

**What happens if secrets are NOT sourced:**
- Tests 1-10 (--run mode): **FAIL** — AI CLI cannot authenticate. Error: `ERROR: * AI failed`
- `assert-*` scripts still run: they check seed data (which hasn't been modified by AI)
- `run-e2e-ai.sh` will report `N passed, M failed` with M = number of --run tests

**What happens if `opencode` is not in PATH:**
- Fallback to `claude` (if installed and `ANTHROPIC_API_KEY` is set)
- If neither available: all --run tests fail
- Seed + assert still run (they don't need AI)

**Running without AI (cheap + fast, ~10 sec, no secrets):**
```bash
# Runs seed + assert for all 14 tests — no AI, no secrets
for phase in quick-close wp-new day-close week-close day-open \
  strategy-session session-prep wp-gate orz-cycle note-review \
  archgate intgate role-exec skill-invoke; do
  bash scripts/test/e2e/run-e2e-ai.sh "$phase"
done
# Each phase: seed created ✓, --run SKIPPED (no secrets), assert checked ✓
```

### 4. Canary Tests — `scripts/test/canary-*.sh`

**2 tests**, weekly frequency, AI CLI required. Detect model/prompt degradation.

```bash
bash scripts/test/canary-day-close.sh <workspace> --run   # replay Day Close
bash scripts/test/canary-wp-gate.sh --run                 # emulate WP Gate
```

| Test | What it does |
|------|-------------|
| `canary-day-close.sh` | Copies workspace → runs Day Close → compares diff |
| `canary-wp-gate.sh` | Creates workspace without task → requests it → asserts STOP |

### 5. E2E Tests (Structural) — `scripts/test/e2e/e2e-*.sh`

**5 tests**, deterministic. Test setup/update/migration workflows without AI.

```bash
bash scripts/test/run-e2e.sh
```

| Test | What it validates |
|------|-------------------|
| `e2e-fresh-install.sh` | Fresh workspace installation |
| `e2e-update-flow.sh` | Update check/apply, NEVER-TOUCH |
| `e2e-conflict.sh` | 3-way merge, conflict detection |
| `e2e-migration.sh` | Symlink repair migration |
| `e2e-author-sync.sh` | template-sync.sh pipeline |

### 6. Container Tests — `scripts/container/test-from-container.sh`

**10 phases**, Podman container. Reproducible CI environment.

```bash
# Build once
bash scripts/container/build-container.sh

# Run phases
bash scripts/container/test-from-container.sh --phase 1     # clean install
bash scripts/container/test-from-container.sh --phase 5c    # unit tests
bash scripts/container/test-from-container.sh --phase all   # full CI suite (1-4, 5a, 5c, 5d, 5f)
```

| Phase | Name | What it runs |
|:-----:|------|-------------|
| 1 | Clean Install | `setup.sh --validate`, workspace creation |
| 2 | Update | `update.sh --check`, `update.sh --apply` |
| 3 | AI Smoke | opencode version, shell commands, file reads |
| 4 | CI + Migrations | `enforce-semver.sh`, migrations, ShellCheck |
| 5a | Strategy Session (structural) | Script dispatch, prompt structure |
| 5b | Strategy Session (headless E2E) | Full AI session with seed |
| **5c** | **Unit Tests** | `run-phase0.sh` (47 tests) |
| **5d** | **E2E Structural** | 14 seed+assert (no AI) |
| **5e** | **Systemd Timers** | `systemd-analyze verify` on services/timers |
| **5f** | **Role Behavioral** | bash -n for all 6 role scripts |

---

## Directory Map

```
scripts/
├── test/                           # All test files
│   ├── test-*.sh                   # 47 unit tests (bash assertions)
│   ├── assert-*.sh                 # 15 assert scripts (structural invariants)
│   ├── seed-*.sh                   # 17 seed scripts (workspace creation)
│   ├── eval-*.sh                   # 17 eval scripts (LLM-judge + --run)
│   ├── rubrics-*.yaml              # 15 rubrics (scoring criteria, 8 metrics each)
│   ├── canary-*.sh                 # 2 canary tests (weekly replay)
│   ├── run-phase0.sh               # Unit test orchestrator
│   ├── run-e2e.sh                  # E2E test orchestrator (structural)
│   ├── _parse_judge_output.py      # LLM judge JSON parser
│   └── e2e/
│       ├── run-e2e-ai.sh           # E2E AI orchestrator (14 workflows)
│       ├── e2e-*.sh                # 5 structural E2E tests
│       ├── _lib.sh                 # E2E shared library
│       └── SMOKE-TEST.md           # Manual smoke test instructions
├── vm/
│   ├── test-phases.sh              # Container/VM test phases (1-5f)
│   ├── test-from-golden.sh         # QEMU/KVM golden image runner
│   └── build-golden.sh             # Golden image builder
├── container/
│   ├── Containerfile               # Ubuntu 24.04 with all tools
│   ├── build-container.sh          # Podman container builder
│   └── test-from-container.sh      # Container test runner (10 phases)
└── ai-cli-wrapper.sh               # AI provider abstraction (claude ↔ opencode)
```

## Naming Conventions

| Pattern | Purpose | Example |
|---------|---------|---------|
| `test-<subject>.sh` | Unit test with assertions | `test-memory-limits.sh` |
| `assert-<workflow>.sh` | Structural invariant check | `assert-day-close.sh` |
| `seed-<workflow>.sh` | Creates workspace with data | `seed-day-close.sh` |
| `eval-<workflow>.sh` | AI process + LLM judge | `eval-day-close.sh` |
| `rubrics-<workflow>.yaml` | Scoring criteria (8 metrics) | `rubrics-day-close.yaml` |
| `canary-<workflow>.sh` | Weekly health replay | `canary-day-close.sh` |
| `e2e-<scenario>.sh` | Structural E2E test | `e2e-fresh-install.sh` |

## Secrets & AI CLI

AI tests require API access. Secrets are loaded from:

| Environment | Secrets location |
|-------------|-----------------|
| **Local** | `~/.iwe-test-vm/secrets/.env` → `AI_CLI_API_KEY`, `AI_CLI_MODEL`, `DEEPSEEK_API_KEY` |
| **Container** | `~/secrets/.env` (uploaded by `test-from-container.sh`) |
| **CI** | GitHub Secrets → `AI_CLI_API_KEY`, `ANTHROPIC_API_KEY` |

Provider auto-detection chain (see `scripts/ai-cli-wrapper.sh`):
```
AI_CLI env var → claude (PATH) → opencode (PATH) → error
```

## Test Metrics

| Metric | Value |
|--------|:----:|
| Total test files | **103** (47 unit + 15 assert + 17 seed + 17 eval + 7 E2E) |
| Unit test pass rate | **47/47** |
| E2E structural pass rate | **5/5** |
| AI E2E workflows | **14** |
| Assert scripts | **15** |
| Canary tests | **2** |
| Container CI phases | **10** |
| Rubrics YAML files | **15** |
| Production scripts with bash -n | **52/52 (100%)** |
| IWE workflow coverage | **95%+** |

---

*Created: 2026-05-08. Updated on every test infrastructure change.*
