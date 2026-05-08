# Role Test Coverage Plan

> Created: 2026-05-08
> Based on: `docs/workflow-full.md` §12 (Роли), §14 (Инфраструктура)
> Current state: 3 structural tests, 0 behavioral/E2E tests

---

## Inventory

### Role Scripts (20)

| Role | Scripts | bash -n | Install | Timer |
|------|---------|:------:|:------:|:-----:|
| **strategist** | `strategist.sh`, `fetch-wakatime.sh` | ✅ | ✅ tested | 2 plist + 4 systemd |
| **extractor** | `extractor.sh` | ✅ | ❌ | 1 plist + 2 systemd |
| **synchronizer** | `scheduler.sh`, `notify.sh`, `code-scan.sh`, `daily-report.sh`, `dt-collect.sh`, `sync-files.sh`, `video-scan.sh` | ✅ | ❌ | 1 plist + 2 systemd |
| **verifier** | `verifier.sh` | ✅ | ❌ | none |
| **auditor** | `auditor.sh` | ✅ | ❌ | none |

### Timer/Config Files (12)

| Role | macOS (launchd) | Linux (systemd) |
|------|----------------|-----------------|
| strategist | 2 plist | 2 service + 2 timer |
| extractor | 1 plist | 1 service + 1 timer |
| synchronizer | 1 plist | 1 service + 1 timer |

### Role Prompts (36 markdown files)

| Role | Prompt Files |
|------|-------------|
| strategist | `session-prep.md`, `strategy-session.md`, `day-plan.md`, `evening.md`, `note-review.md`, `week-review.md`, `add-wp.md`, `check-plan.md`, `day-close.md`, `day-open-test.md`, `strategy-session-test.md` |
| extractor | `inbox-check.md`, `knowledge-audit.md`, `session-close.md`, `on-demand.md`, `health-test.md` |
| verifier | `verify-pack-entity.md`, `verify-content.md`, `verify-wp-acceptance.md` |
| auditor | `audit-plan-consistency.md`, `audit-coverage.md` |

### Role Config (7 YAML files)

| File | Purpose |
|------|---------|
| `roles/MANIFEST.yaml` | Role registry manifest |
| `*/role.yaml` (5) | Per-role definition: ID, scenarios, triggers |
| `synchronizer/config.yaml` | Synchronizer-specific config |

---

## Phase R1: Install Scripts & Timer Validation

> **Type:** bash unit tests — no LLM required
> **Priority:** P0 — roles cannot run without correct installation
> **New test files:** 4

| # | Test file | What it tests | Assertions |
|---|-----------|---------------|:----------:|
| R1.1 | `test-role-install-scripts.sh` | All 5 install.sh: bash -n, shebang, required args (--workspace-dir, --ai-cli-path), OS detection branches | ~20 |
| R1.2 | `test-role-launchd-syntax.sh` | All 4 plist files: valid XML, required keys (Label, ProgramArguments, StartInterval), paths exist | ~15 |
| R1.3 | `test-role-systemd-syntax.sh` | All 8 systemd files: valid INI sections (Unit, Service, Timer), required keys (ExecStart, OnCalendar), paths exist | ~15 |
| R1.4 | `test-role-timer-consistency.sh` | Timer→Service pairing: every .timer references existing .service, every .service has matching .timer (or standalone) | ~10 |

## Phase R2: Role Script Behavioral Tests

> **Type:** bash unit tests — no LLM required
> **Priority:** P1 — structural correctness of role execution
> **New test files:** 4

| # | Test file | What it tests | Assertions |
|---|-----------|---------------|:----------:|
| R2.1 | `test-role-strategist.sh` | `strategist.sh`: bash -n, usage message, `--scenario` arg, scenario routing (morning, evening, session-prep, etc.), prompt file references resolve | ~12 |
| R2.2 | `test-role-synchronizer.sh` | All 7 synchronizer scripts: bash -n, `notify.sh` env requirements, `scheduler.sh` structure, template files exist for each agent | ~15 |
| R2.3 | `test-role-extractor-verifier-auditor.sh` | `extractor.sh`, `verifier.sh`, `auditor.sh`: bash -n (already covered), usage/help, `--scenario` arg, prompt file references resolve | ~12 |
| R2.4 | `test-role-prompt-coverage.sh` | All 36 prompt .md files: non-empty, have frontmatter or title, referenced by at least one role script | ~12 |

## Phase R3: Role E2E Tests (AI Smoke)

> **Type:** LLM-as-Judge (DeepSeek) — requires AI CLI
> **Priority:** P2 — validates that AI can execute roles correctly
> **New test files:** 6 (3 seed + 3 eval/rubrics)

| # | Test | What it tests | Steps |
|---|------|---------------|:-----:|
| R3.1 | `extractor-inbox-check-e2e` | Extractor reads inbox, classifies notes, routes knowledge. Seed: fleshing-notes + captures. Eval: correct routing to Pack/CLAUDE.md/memory/ | ~8 |
| R3.2 | `verifier-pack-entity-e2e` | Verifier checks Pack entity against DP standard. Seed: Pack file + expected violations. Eval: correct violation detection | ~6 |
| R3.3 | `synchronizer-code-scan-e2e` | Synchronizer scans codebase, reports drift. Seed: modified template files vs upstream. Eval: correct drift detection | ~8 |

---

## Summary

| Phase | Priority | Files | Assertions | Type | Depends on |
|-------|:--------:|:-----:|:----------:|------|------------|
| R1 — Install & Timers | **P0** | 4 | ~60 | bash unit | None |
| R2 — Behavioral | **P1** | 4 | ~51 | bash unit | R1 |
| R3 — E2E AI Smoke | **P2** | 6 | ~22 | LLM-as-Judge | R2 + AI CLI |
| **Total** | | **14** | **~133** | | |

### After completion

| Metric | Current | Target |
|--------|:------:|:------:|
| Role install scripts tested | 1/5 | **5/5** |
| Timer/config files tested | 0/12 | **12/12** |
| Role scripts with behavioral tests | 0/15 | **15/15** |
| Role E2E AI tests | 0 | **3** |
| Role prompt coverage validated | 0/36 | **36/36** |

---

*Created: 2026-05-08*
