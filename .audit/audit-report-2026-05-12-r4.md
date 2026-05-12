# Test Suite Audit Report — FMT-exocortex-template (Re-audit #4)

**Date:** 2026-05-12
**Auditor:** Claude (test-suite-auditor skill)
**Previous audits:** 2026-05-07, 2026-05-10, 2026-05-12 (#3)
**Scope:** All `.sh` scripts under `scripts/test/`, `lib/`, `.claude/hooks/`, `.claude/scripts/`, `scripts/lib/`, `roles/synchronizer/tests/`, plus CI workflows under `.github/workflows/`.

---

## TL;DR

**Maturity:** **3** / 5 (stable). All four P0/P1 blockers from audit #3 are fixed locally. Phase0 at **100% (61/61)** — up from 98.1%. E2E at **100% (5/5)**. BATS integrated into phase0 runner. New lib tests created (355 lines) closing P1-GAP-01. CI is blocked only by the fix not yet being committed/pushed — a process issue, not a code issue.

**Top priority:** Commit + push the existing fixes to unblock CI. Then track || true / 2>/dev/null trend weekly.

---

## Inventory

### Stack (unchanged)

| Aspect | Value |
|---|---|
| Language / runtime | Bash 5 |
| Test frameworks | Custom (_pass/_fail) + BATS 1.10.0 |
| Mocking / fixtures | Temp directories (mktemp + trap), function mocking |
| Coverage tool | _not present_ |
| Mutation tool | _not present_ |
| CI runner | GitHub Actions |
| Total .sh files | 204 |

### Suite distribution (2026-05-12 R4 vs R3)

| Layer | Count | Delta | Pass rate |
|---|---|---|---|
| Unit (test-*.sh) | 55 | +2 | 100% (55/55) |
| Assert (assert-*.sh) | 19 | 0 | not run (AI) |
| Eval (eval-*.sh) | 18 | 0 | not run (AI) |
| Seed (seed-*.sh) | 18 | 0 | not run (AI) |
| Canary (canary-*.sh) | 5 | 0 | not run (AI) |
| E2E (e2e-*.sh) | 5 | 0 | 100% (5/5) |
| BATS (*.bats) | 6 | 0 | 100% (6/6, integrated) |
| Runners + libs | 4 | 0 | — |
| **Total** | **130** | +4 | |

**New:** test-lib-env.sh (169L, ~30 checks), test-lib-telegram.sh (185L, ~28 checks) — both pass.

### Metrics snapshot

| Metric | R4 | R3 | R1 | Trend |
|---|---|---|---|---|
| Phase0 pass rate | **100% (61/61)** | 98.1% | 85.7% | ↗ |
| E2E pass rate | **100% (5/5)** | 100% | 100% | → |
| BATS integrated | **Yes (phase0)** | No | N/A | ↗ |
| \|\| true instances | 175 | 174 | 16 | ↘ (slowing) |
| 2>/dev/null instances | 736 | 711 | — | ↘ (slowing) |
| mktemp without trap | **0** | 0 | 0 (FP) | → |
| CI pass rate (remote) | **0% (5/5)** | 0% | — | → fix uncommitted |
| CI pass rate (local) | **100%** | 0% | — | fix exists |
| Untracked changes | 8 files | — | — | new |
| Strict mode (scope) | 100% test files | 100% test files | 64% | → |

---

## Findings

### Resolved since audit #3

| ID | Status | Note |
|----|--------|------|
| P0-BUG-01 | **FIXED** | Orphan `.pyc` entry removed; checksums.yaml now references directory. test-checksums.sh: 0 orphans. |
| P0-CI-01 | **FIXED pending push** | Root cause resolved. Local run: 61/61 passed. |
| P0-ANTI-01 | **FIXED** | run-e2e-ai.sh captures stderr to log files, displays on failure. Lines 27, 58, 72, 89. |
| P1-GAP-01 | **FIXED** | test-lib-env.sh + test-lib-telegram.sh created (355 lines, ~58 checks). |

---

### P1 — significantly slows the team or erodes confidence

#### P1-CI-01-UPDATED: CI still failing — fix uncommitted

- **What:** All 5 recent CI runs fail because the checksums.yaml fix (P0-BUG-01 resolution) exists only in the working tree, not in the committed/pushed state that CI tests against. Local run-phase0.sh passes 61/61.
- **Evidence:** `checksums.yaml:15` (fixed locally), `gh run list` showing 5/5 failures, `bash scripts/test/run-phase0.sh` → 61 passed
- **Source:** SWE@Google Ch.11 — CI gates must reflect current state
- **Fix:** Commit + push working tree changes (checksums.yaml, run-e2e-ai.sh, new test files)
- **Effort:** S

#### P1-PROC-01: || true and 2>/dev/null growth

- **What:** Error suppression patterns grew slightly since audit #3: `|| true` 174→175 (+1), `2>/dev/null` 711→736 (+25). Growth is slowing (was +18 each in previous audit), but cumulative 911 suppressions in 55-test-file suite is elevated.
- **Evidence:** `scripts/test/test-ai-cli-wrapper.sh:12 || true` (top), canary-wp-gate.sh:6, test-extension-points.sh:8
- **Source:** Google Testing Blog; failure-injection-gate.md (command substitution without exit check)
- **Fix:** Cap new instances. Weekly audit of top-10 offenders. Replace with stderr-capture pattern.
- **Effort:** M

---

### P2 — quality/hygiene/future-proofing

#### P2-ANTI-01: lib-telegram python3 error masking

- **What:** `lib/lib-telegram.sh:42` uses `python3 -c '...' 2>/dev/null` — if python3 crashes on malformed JSON response, the error is swallowed. Function correctly returns rc=1 (behavior is right), but diagnostic is lost.
- **Evidence:** `lib/lib-telegram.sh:42` — `ok=$(echo "$response" | python3 ... 2>/dev/null)`
- **Source:** bash manual §Shell Builtin Commands; failure-injection-gate.md
- **Fix:** Capture stderr to variable, display on failure. Or add python3 availability check.
- **Effort:** S

#### P2-PROC-02: 8 files untracked/uncommitted

- **What:** Working tree has 6 modified files + 2 new test files + stale backup files. All fixes from audit #3 live in the working tree only.
- **Evidence:** `git status` showing M: checksums.yaml, run-e2e-ai.sh, canary-wp-gate.sh, run-phase0.sh, generate-checksums.sh, lib-telegram.sh; ??: test-lib-env.sh, test-lib-telegram.sh
- **Source:** SWE@Google Ch.11 — untracked tests are invisible to CI
- **Fix:** Stage and commit all changes. Remove stale backups (.migration backup, protocol-close backup).
- **Effort:** S

---

## Cross-Reference: Audit #3 → R4 Resolution Map

```
Audit #3            → R4 Status
──────────────────────────────────
P0-BUG-01           → FIXED (checksums.yaml orphan removed)
P0-CI-01            → FIXED pending push (local 61/61 passes)
P0-ANTI-01          → FIXED (stderr capture to log files)
P1-GAP-01           → FIXED (test-lib-env.sh, test-lib-telegram.sh)
P1-ANTI-01          → not re-audited (unchanged scope)
P1-ANTI-02          → not re-audited
P1-ANTI-03          → not re-audited
P1-GAP-02           → not re-audited
P2-ANTI-01          → not re-audited
P2-ANTI-02          → not re-audited
P2-ANTI-03          → not re-audited
P2-PROC-01          → not re-audited
```

---

## Definition of Done (for this re-audit cycle)

| Criterion | Current | Target |
|-----------|---------|--------|
| Phase0 pass rate | 100% (61/61) | 100% |
| E2E pass rate | 100% (5/5) | 100% |
| CI pass rate | 0% (fix uncommitted) | 100% |
| || true instances | 175 | ≤ 170 |
| 2>/dev/null instances | 736 | ≤ 700 |
| Untracked changes | 8 files | 0 files |
| New lib test coverage | 2 new tests created | N/A (done) |

---

*Report generated: 2026-05-12. Full findings in `.audit/findings-2026-05-12-r4.json`.*
