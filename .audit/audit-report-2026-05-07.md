# IWE Testing System — Audit Report

> **Date:** 2026-05-07
> **Scope:** Full test suite (28 test files, 5 E2E suites, VM/container infrastructure)
> **Methodology:** SOTA 2026 cross-reference × full-code audit × comparison with 2026-05-06 audit
> **Findings:** 20 total (4 P0, 10 P1, 6 P2)
> **Baseline:** 14 unit tests, 12 pass / 2 fail (85.7%), 5 E2E all pass, 395 assertions

---

## 1. Executive Summary

| Metric | Value |
|--------|-------|
| Maturity Score | **2/5** (Repeatable — tests exist, but gaps in structure, coverage, and tooling) |
| Unit Test Pass Rate | 85.7% (12/14) |
| E2E Pass Rate | 100% (5/5) |
| Production Scripts Tested | 8 of 22 (36%) |
| Critical Path Coverage | 64% (hooks and AI wrapper untested) |
| Previous Audit Findings Fixed | 3 of 40 (C1, C3, C4) |

### What We Do Right
- Deterministic checks before LLM-judge (correct ordering in AI smoke tests)
- Ephemeral environments (COW clone for VM, `podman rm -f` for container)
- Idempotent infrastructure (build-*.sh skip if exists)
- Security scanning in CI (Trivy)
- Debug mode with full artifact preservation
- Consistent `_pass/_fail` assertion pattern across all tests
- ShellCheck in CI (validate-template.yml)

### Blind Spots
- **Traceability:** No per-LLM-call tracing (model, tokens, latency)
- **Continuous shadow evaluation:** No drift detection
- **Regression dataset:** Each run from scratch, no historical comparison
- **Cross-provider benchmarking:** Only judge cross-provider, not generator
- **CI gates:** No flake detection, no coverage diff gate, no mutation gate
- **Observability:** Internal state, memory access, tool calls not traced

---

## 2. Inventory

| Layer | Count | Framework | Runner |
|-------|:-----:|-----------|--------|
| Unit Tests | 14 | custom `_pass`/`_fail` | `scripts/test/run-phase0.sh` |
| E2E Tests | 5 | custom + `_lib.sh` | `scripts/test/run-e2e.sh` |
| AI Smoke Tests | 6 | LLM-as-Judge (DeepSeek) | CI only (`test-golden.yml`) |
| VM Tests | 10 | QEMU/KVM golden image | CI only (`test-golden.yml`) |
| Container Tests | 3 | Podman | CI only (`test-container.yml`) |
| **Total** | **38** | | |

| Production Scripts | Count |
|--------------------|:-----:|
| Core (`setup.sh`, `update.sh`, `template-sync.sh`) | 3 |
| Scripts (`scripts/*.sh`, `scripts/lib/`) | 4 |
| Hooks (`.claude/hooks/*.sh`) | 7 |
| Claude Scripts (`.claude/scripts/`) | 2 |
| Migrations | 5 |
| **Total** | **22** |

---

## 3. Findings Summary

### P0 — Critical (4)

| ID | Title | Category | Effort |
|----|-------|----------|:------:|
| P0-BUG-01 | test-update-check.sh crashes silently — grep `\|` + set -e abort | bug | M |
| P0-BUG-02 | test-manifest-files.sh legitimately fails — version 0.28.0 != CHANGELOG 0.28.1 | bug | S |
| P0-GAP-01 | 9 production scripts completely untested (542 lines, no bash -n, no coverage) | white-spot | L |
| P0-GAP-02 | ai-cli-wrapper.sh — central AI abstraction layer, zero behavioral tests | white-spot | M |

### P1 — High (10)

| ID | Title | Category | Effort |
|----|-------|----------|:------:|
| P1-ANTI-01 | run-phase0.sh, run-e2e.sh lack `set -e` — can silently skip failures | antipattern | S |
| P1-ANTI-02 | 10 test files missing `set -euo pipefail` (all E2E tests) | antipattern | M |
| P1-ANTI-03 | seed-day-open.sh: 11 `|| true` mask git operation errors | antipattern | M |
| P1-BUG-01 | test-phases.sh: grep && _ok without \|\| _fail (M1 from prev audit, unfixed) | bug | S |
| P1-BUG-02 | test-update-check.sh runs real update.sh --check — slow, not hermetic | antipattern | M |
| P1-GAP-01 | 16/28 test files without trap cleanup — temp file leaks | quality | S |
| P1-GAP-02 | test-manifest-files.sh: YAML validation skipped (only ruby tried, python3 available) | white-spot | S |
| P1-GAP-03 | No ShellCheck in local test suite — only bash -n | white-spot | M |

### P2 — Low (5)

| ID | Title | Effort |
|----|-------|:------:|
| P2-QUAL-01 | run-phase0.sh grep filter truncates assertion output | S |
| P2-QUAL-02 | e2e/_lib.sh — shared E2E library has no tests | S |
| P2-QUAL-03 | test-update-check.sh:76 uses GNU grep `\|` extension — not POSIX | S |
| P2-QUAL-05 | migrations/_template.sh excluded from bash -n | S |
| P2-QUAL-06 | No test coverage map in MEMORY.md or navigation.md | S |

---

## 4. Detailed Findings

### P0-BUG-01 — test-update-check.sh crashes silently

**File:** `scripts/test/test-update-check.sh:73-76`

The test uses `\|` alternation in basic grep (line 76), which is a GNU extension. On BSD/macOS grep, this causes exit code 2 (syntax error). Combined with `set -e`, the script aborts silently. Additionally, the test runs the REAL `update.sh --check` (lines 45, 73) which does git fetch + checksum generation — expensive and not hermetic.

**Fix:**
1. Replace `\|` with `grep -E "symlink.*broken|symlink.*missing"`
2. Mock `update.sh` --check instead of running real git operations
3. Add explicit handling for grep exit 2

**Source:** SWE@Google Ch.11 — tests must be hermetic; Google Testing Blog flaky-tests series

---

### P0-BUG-02 — MANIFEST version skew

**File:** `MANIFEST.yaml:3` vs `CHANGELOG.md`

Root MANIFEST.yaml declares version `0.28.0`. CHANGELOG.md latest entry is `0.28.1`. This is a legitimate version mismatch caught by `test-manifest-files.sh`. Either MANIFEST is stale or CHANGELOG was prematurely bumped.

**Fix:** Bump MANIFEST.yaml to `0.28.1` or revert CHANGELOG.

**Source:** SWE@Google Ch.12 — tests must be reliable indicators

---

### P0-GAP-01 — 9 untested hooks and scripts

**Files:** All `.claude/hooks/*.sh` (7 files, 381 lines) + `.claude/scripts/*.sh` (2 files, 161 lines)

These 9 scripts have ZERO test coverage — no `bash -n`, no ShellCheck, no behavioral tests. The 7 hooks gate the AI session lifecycle (OPZ protocol, workspace resolution, artifact validation). A bug in any hook silently corrupts the AI's work context.

**Fix:** Phase 1: Add bash -n + ShellCheck for all 9 scripts. Phase 2: Add unit tests for critical hooks (protocol-stop-gate.sh, protocol-artifact-validate.sh). Phase 3: Add integration tests for workspace resolution (resolve-workspace.sh).

**Source:** SWE@Google Ch.11 — Beyoncé Rule

---

### P0-GAP-02 — ai-cli-wrapper.sh untested

**File:** `scripts/ai-cli-wrapper.sh`

The single abstraction over all LLM calls (Claude Code ↔ OpenCode). A bug here affects every AI test and all production AI interactions. Previous C4 bug (broken --allowedTools flag, fixed 2026-05-06) was found manually — proving the test gap is real.

**Fix:** Add behavioral tests: flag construction (no embedded quotes), fallback logic (mock claude unavailable), tools parsing, exit code propagation.

**Source:** SWE@Google Ch.11 — Beyoncé Rule; Khorikov — test the boundaries real callers use

---

## 5. Baseline Metrics

| Metric | Before | Note |
|--------|--------|------|
| Unit pass rate | 85.7% (12/14) | P0-BUG-01 and P0-BUG-02 cause failures |
| E2E pass rate | 100% (5/5) | All pass, but lack set -e (P1-ANTI-02) |
| Scripts with bash -n | 8/22 (36%) | Only tested scripts get syntax check |
| Scripts with ShellCheck | 0/22 (0%) | Only in CI, not local |
| Scripts with behavioral tests | 8/22 (36%) | 14 scripts untested or loop-only |
| Trap cleanup in tests | 12/28 (43%) | 16 tests leak temp files |
| set -euo pipefail in tests | 18/28 (64%) | All E2E tests lack it |
| CI wall time (container) | ~90s | All recent CI runs: success |
| Coverage tooling | `null` | No bash coverage tool exists |
| Mutation tooling | `null` | No bash mutation tool exists |

---

## 6. Comparison with Previous Audit (2026-05-06)

| Aspect | 2026-05-06 Audit | 2026-05-07 Audit | Delta |
|--------|:---:|:---:|------|
| Total Findings | 40 | 20 | Different scope (prev: 8 files/~2000 lines, this: full suite) |
| P0/Critical | 4 | 4 | C1,C3,C4 fixed; new P0 gaps found |
| P1/High | 5 | 11 | Expanded scope reveals more structural issues |
| P2/Low | 20 | 5 | Previous audit had deeper VM/container analysis |
| Coverage Gap (hooks) | Not covered | 9 scripts/542 lines | New finding — previous audit didn't scan hooks |
| Version Skew | Not found | 0.28.0 vs 0.28.1 | Regression since yesterday |
| ai-cli-wrapper | C3,C4 fixed | Still no behavioral tests | Fixes applied to bugs, not to test coverage gap |

### Previously Identified, Still Unfixed

| Finding | Status |
|---------|--------|
| M1 — grep && _ok without \|\| _fail | Still exists in test-phases.sh:56-58 → P1-BUG-01 |
| M2-M11 | Not verified in this audit (VM/container scope) |
| L1-L20 | Not verified |

---

## 7. Definition of Done (Numerical Exit Criteria)

| Criterion | Current | Target |
|-----------|:------:|:------:|
| Unit test pass rate | 85.7% | **100%** |
| Production scripts with bash -n | 8/22 (36%) | **22/22 (100%)** |
| Production scripts with ShellCheck | 0/22 (0%) | **22/22 (100%)** |
| Scripts with behavioral tests | 8/22 (36%) | **15/22 (68%)** — critical path: hooks, ai-cli-wrapper, resolve-workspace |
| Test files with set -euo pipefail | 18/28 (64%) | **28/28 (100%)** |
| Test files with trap cleanup | 12/28 (43%) | **28/28 (100%)** |
| `|| true` in test seed scripts | 16 instances | **0** — explicit error handling only |
| CI gates | 0 blocking gates | **3** — ShellCheck gate, no-flake-merge gate, coverage diff gate (advisory) |

---

## 8. Remediation Roadmap

### Week 1 — Quick Wins (P0 bugs + P1 structural, ~30 min)

```
P0-BUG-02 (version skew) → P1-ANTI-01 (set -e in runners) → P1-ANTI-02 (set -e in all tests) →
P1-GAP-01 (trap cleanup) → P1-BUG-03 (workspace mutation)
```

### Week 2 — Critical Coverage (P0 gaps, ~45 min)

```
P0-GAP-02 (ai-cli-wrapper tests) → P0-GAP-01 (hooks bash -n + tests)
```

### Week 3-4 — System Hardening (P1 quality + P2, ~1.5 h)

```
P0-BUG-01 (test-update-check fix) → P1-BUG-01 (grep && _ok fix) →
P1-BUG-02 (mock update.sh) → P1-GAP-03 (ShellCheck local) →
P1-GAP-02 (YAML validation) → P2 items
```

---

## 9. ADR — Architecture Decision Records

### ADR-001: Bash Test Structure — Mandatory Strict Mode

**Decision:** All test scripts must use `set -euo pipefail`. All production scripts must pass `bash -n` and ShellCheck severity=warning.

**Rationale:**
- 36% of test files lack `set -e`, risking silent false positives
- 64% of production scripts lack bash -n
- 100% of production scripts lack ShellCheck locally
- Consistency in strict mode prevents the "it worked yesterday" class of bugs

**Alternatives considered:**
- Per-file strict mode (rejected: inconsistency is the problem)
- ShellCheck only in CI (rejected: developer feedback loop must be shorter)

---

### ADR-002: Test Coverage Map as Part of MEMORY.md

**Decision:** Maintain a `production → test` mapping in MEMORY.md or a new `TEST-COVERAGE.md` file.

**Rationale:**
- Without a map, coverage gaps are invisible
- 9 scripts with zero tests were unknown until this audit
- Auto-generation from grep patterns is cheap and prevents drift

---

*Report generated: 2026-05-07. Based on full-suite audit with code-level evidence.*
