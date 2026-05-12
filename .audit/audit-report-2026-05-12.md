# Test Suite Audit Report — FMT-exocortex-template (Re-audit #3)

**Date:** 2026-05-12
**Auditor:** Claude (test-suite-auditor skill)
**Previous audit:** 2026-05-10 (`.audit/audit-report-2026-05-10.md`)
**First audit:** 2026-05-07 (`.audit/audit-report-2026-05-07.md`)
**Scope:** All `.sh` scripts under `scripts/test/`, `lib/`, `.claude/hooks/`, `.claude/scripts/`, `scripts/lib/`, `roles/synchronizer/tests/`, plus CI workflows under `.github/workflows/`.

---

## TL;DR

**Maturity:** **3** / 5. CI regressed (5/5 runs failing), but strict mode (100%), trap hygiene (0 leaks), and E2E tests (100%) are preserved. One priority fix: remove orphan __pycache__ entry from checksums.yaml — this single fix unblocks CI. 18 commits landed since last audit with mixed quality: new BATS tests added but not integrated, lib/ libraries added without tests, || true continued to grow (174, +18).

**Top three problems:**

1. **P0-BUG-01: test-checksums.sh orphan __pycache__ entry** — `scripts/test/__pycache__/_parse_judge_output.cpython-312.pyc` in checksums.yaml but not on disk. Cascading failure: test → phase0 runner → CI. 5/5 CI runs failing.
2. **P0-ANTI-01: run-e2e-ai.sh masks ALL subprocess stderr** — 18 AI E2E workflows, 711 total 2>/dev/null instances across test suite. Seed check is now verified, but eval/judge/assert still masked.
3. **P1-GAP-01: lib/lib-env.sh + lib/lib-telegram.sh** — 114 lines of new production code, zero tests. Telegram lib swallows curl/python3 errors silently.

---

## Inventory

### Stack (unchanged)

| Aspect | Value |
|---|---|
| Language / runtime | Bash 5 |
| Config formats | YAML, JSON, Markdown |
| Test frameworks | Custom (_pass/_fail) + BATS (new, 6 files) |
| Mocking / fixtures | Temp directories (mktemp), git worktrees |
| Coverage tool | _not present_ |
| Mutation tool | _not present_ |
| CI runner | GitHub Actions |
| CI runtime | ShellCheck + phase0: 85s |

### Suite distribution (2026-05-12 vs 2026-05-10)

| Layer | Count | Delta | Pass rate |
|---|---|---|---|
| Unit (test-*.sh) | 53 | +2 | 98.1% (52/53) |
| Assert (assert-*.sh) | 19 | +1 | not run |
| Eval (eval-*.sh) | 18 | +1 | not run |
| Seed (seed-*.sh) | 18 | +1 | not run |
| Canary (canary-*.sh) | 5 | 0 | not run |
| E2E (e2e-*.sh) | 6 | +1 | 100% (6/6) |
| BATS (*.bats) | 6 | +6 | not run |
| Runners + libs | 4 | 0 | — |
| **Total** | **129** | +12 | |

**New since last audit:** BATS test framework (6 files in `roles/synchronizer/tests/`), 1 new E2E test, 1 new unit test, asserts/evals/seeds expanded.

### Metrics snapshot

| Metric | 2026-05-12 | 2026-05-10 | 2026-05-07 | Trend |
|---|---|---|---|---|
| Phase0 pass rate | 98.1% (52/53) | 98% (50/51) | 85.7% (12/14) | ↗ |
| E2E pass rate | 100% (6/6) | 100% (5/5) | 100% (5/5) | → |
| Strict mode | **100% (125/125)** | 100% (117/117) | 64% (18/28) | → |
| \|\| true instances | **174** | 156 | 16 | ↘ |
| mktemp without trap | **0** ✅ | 18 | 0 (FP) | ↗ |
| 2>/dev/null instances | **711** | not measured | not measured | new |
| CI pass rate | **0% (0/5)** | 0% (0/5) | not measured | → |
| Untested prod scripts | 6 | 26 | 9 | ↗ (diff scope) |
| ShellCheck local | not installed | not installed | not installed | → |

---

## Findings

### P0 — actively misleading or hiding bugs

#### P0-BUG-01: test-checksums.sh orphan __pycache__ entry

- **What:** `checksums.yaml:190` has an entry for `scripts/test/__pycache__/_parse_judge_output.cpython-312.pyc` which doesn't exist on disk. The orphan check in test-checksums.sh catches this legitimately, but since run-phase0.sh runs test-checksums.sh AND CI runs run-phase0.sh, this single stale entry cascades into a full CI pipeline failure.
- **Evidence:** `checksums.yaml:190`, `scripts/test/test-checksums.sh:122-124`, CI 5/5 runs failing
- **Source:** SWE@Google Ch.12 Principle 1 — reliable indicators
- **Fix:** Delete orphan from checksums.yaml, add `__pycache__/` to never_touch list
- **Effort:** S

#### P0-CI-01: CI failing ALL runs

- **What:** validate-template.yml expanded shellcheck job to run full phase0 suite, but the suite has a failing test (P0-BUG-01). 5/5 recent runs show failure.
- **Sub-finding of P0-BUG-01.** Fix P0-BUG-01 to unblock.
- **Evidence:** `.github/workflows/validate-template.yml:85-94`, `gh run list` all failure
- **Effort:** S (depends on P0-BUG-01)

#### P0-ANTI-01: E2E AI runner masks ALL stderr

- **What:** run-e2e-ai.sh passes ALL subprocess output through `2>/dev/null`. Seed line now has explicit rc check (improved since last audit), but eval/run/judge/assert calls on lines 41, 52, 66 still masked.
- **Evidence:** `scripts/test/e2e/run-e2e-ai.sh:41,52,66`
- **Source:** bash manual §Shell Builtin Commands; Google Testing Blog Flaky Tests series
- **Fix:** Capture stderr to temp files, display on failure
- **Effort:** M

---

### P1 — significantly slows team or erodes confidence

#### P1-GAP-01: lib/ libraries untested (114 lines)

- New since last audit. `lib/lib-env.sh` (workspace resolution, env validation) and `lib/lib-telegram.sh` (Telegram API) have zero test coverage. Telegram lib silently swallows curl/python3 errors.
- **Evidence:** `lib/lib-env.sh:1-70`, `lib/lib-telegram.sh:1-44`, `lib/lib-telegram.sh:42`
- **Effort:** M

#### P1-ANTI-01: 174 || true (+18)

- Continued growth. Top offenders: test-ai-cli-wrapper.sh (12), test-extension-points.sh (8), canary-wp-gate.sh (6). Three categories: safe cleanup, assertion bypass, critical git masking.
- **Effort:** L

#### P1-ANTI-02: 711 2>/dev/null instances

- Diagnostic blackout. When a test fails, there's zero diagnostic info. Combined with || true, creates double-blind.
- **Effort:** L

#### P1-GAP-02: grep -q && without || _fail

- `test-update-check.sh:94` — if grep fails, no assertion recorded. Assertion Roulette antipattern.
- **Effort:** S

#### P1-GAP-03: BATS tests not integrated

- 6 BATS files in `roles/synchronizer/tests/` not discoverable by phase0 or CI.
- **Effort:** S

---

### P2 — quality, hygiene

| ID | Title | Evidence | Effort |
|----|-------|----------|--------|
| P2-BUG-01 | _fail + || true in test-checksums.sh | `test-checksums.sh:54,127` | S |
| P2-QUAL-01 | run-phase0.sh grep filter | `run-phase0.sh:65` | S |
| P2-QUAL-02 | lib-telegram.sh error swallowing | `lib/lib-telegram.sh:42` | S |
| P2-QUAL-03 | lib-env.sh calls python3 without error check | `lib/lib-env.sh:39,57` | S |

---

## Fix-Review: Previous audit findings status

| Finding ID | Title | Status |
|---|---|---|
| P0-BUG-01 (2026-05-10) | test-checksums.sh mutates checksums.yaml | **FIXED** — copy/restore pattern on lines 22-30. New bug: orphan entry in checksums.yaml itself |
| P0-CI-01 (2026-05-10) | CI silently failing | **NOT FIXED** — actually worse: now ALL runs fail instead of 4/6 jobs |
| P0-ANTI-01 (2026-05-10) | E2E AI runner error masking | **PARTIAL** — seed exit check added, eval/assert still masked |
| P0-GAP-01 (2026-05-10) | 26 untested scripts | **IMPROVED** — now 6 untested (scope change: new lib/ files offset gains) |
| P1-ANTI-01 (2026-05-10) | 156 \|\| true instances | **REGRESSED** — 174 now (+18) |
| P1-GAP-01 (2026-05-10) | 18 mktemp without trap | **FIXED** — 0 instances ✅ |
| P1-ANTI-02 (2026-05-10) | 10 files missing strict mode | **FIXED** — 100% strict mode preserved ✅ |
| P1-BUG-01 (2026-05-07) | grep -q && _ok in vm/test-phases.sh | **UNVERIFIED** — VM tests not runnable locally |

---

## Strengths

- **100% strict mode adherence** (125/125 test files) — preserved and expanded (+8 files since last audit)
- **0 mktemp without trap** — fully eliminated (was 18 in 2026-05-10)
- **E2E tests 100% green** (6/6) — expanded from 5 to 6 scenarios
- **test-checksums.sh hermetic fix** — copy/restore pattern is correct, only the __pycache__ data issue remains
- **BATS framework adoption** — properly structured tests with adapters/integration/lib separation

---

## White spots

- **lib/lib-env.sh (70L)** — workspace resolution, env loading, validation. Zero tests.
- **lib/lib-telegram.sh (44L)** — Telegram API, curl calls with error swallowing. Zero tests.
- **roles/shared/lib/lib-notify.sh (34L)** — notification wrapper. Zero tests.
- **scripts/adapters/email.sh (15L), log.sh (17L), slack.sh (15L)** — adapter pattern. Zero tests.
- **BATS tests disconnected** — no runner integration, not in CI.
- **run-e2e-ai.sh stderr masking** — 18 workflows have black-box failures.
- **174 || true instances** — codebase-wide problem requiring systematic audit.

---

## Roadmap

### Immediate (S effort, <1h)

1. **Fix P0-BUG-01: remove orphan __pycache__ from checksums.yaml** (S) — Regenerate checksums with correct file set. Add __pycache__/ to .gitignore. Re-run test-checksums.sh → unblocks CI. *Addresses P0-BUG-01, P0-CI-01.*

### Week 1 — Quick Wins (S/M effort)

2. **Fix P2-BUG-01: remove || true from test-checksums.sh:54,127** (S)
3. **Fix P1-GAP-02: test-update-check.sh grep -q → add || _fail** (S)
4. **Fix P1-GAP-03: integrate BATS into run-phase0.sh** (S) — Add BATS detection and invocation step
5. **Fix P2-QUAL-02: lib-telegram.sh error swallowing** (S) — Remove || echo '' pattern

### Week 2 — Structural Fixes (M effort)

6. **Fix P0-ANTI-01: E2E AI runner stderr capture** (M) — Capture stderr to temp files, display on failure
7. **Fix P1-GAP-01: test lib/lib-env.sh + lib/lib-telegram.sh** (M) — Add dedicated test files, integrate with phase0

### Week 3+ — Investments (L effort)

8. **Reduce || true (P1-ANTI-01)** (L) — Classify all 174 instances, fix error-masking and assertion-bypass. Target: <40 legitimate.
9. **Reduce 2>/dev/null (P1-ANTI-02)** (L) — Systematic audit of 711 instances. Replace blanket stderr suppression with targeted filtering.

---

## Definition of Done (numerical exit criteria)

| Metric | Current | Target | How verified |
|--------|:------:|:------:|-------------|
| Phase0 pass rate | 98.1% (52/53) | **100% (53/53)** | `run-phase0.sh` exit 0 |
| CI pass rate (validate) | 0% (0/5) | **100% (all jobs)** | Check last 5 runs |
| \|\| true (legitimate) | 174 (unclassified) | <40 (classified) | grep count after remediation |
| mktemp without trap | 0 ✅ | 0 (no regression) | grep -L trap on mktemp |
| E2E AI runner stderr capture | 0% captured | **100% captured** | stderr → temp files per stage |
| BATS integration | not in CI | **in phase0 + CI** | runner detects BATS and invokes |
| Untested production scripts | 6 | **0 (all have test)** | test-*.sh for each lib/ and adapter |
| Strict mode | 100% ✅ | 100% (no regression) | grep in all test files |

---

## Sources cited

- Software Engineering at Google, Ch. 11-12 — https://abseil.io/resources/swe-book/html/toc.html
- Meszaros — xUnit Test Patterns (Assertion Roulette antipattern)
- Google Testing Blog — Flaky tests series (Auto-retry, Sleeps as Synchronization)
- bash manual — Shell Builtin Commands (command substitution exit propagation)
- ICSE 2024 — FTW Workshop on Flaky Tests
- Previous audits: `.audit/audit-report-2026-05-07.md`, `.audit/audit-report-2026-05-10.md`
