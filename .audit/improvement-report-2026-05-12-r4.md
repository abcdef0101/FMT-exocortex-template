# Improvement Report — Re-audit #4

**Date:** 2026-05-12
**Baseline:** `.audit/baseline-2026-05-12-r4.json`
**Measurement:** `.audit/measurement-2026-05-12-r4.json`

---

## Before / After

| Metric | Before (R3) | After (R4 Post-fix) | Change |
|--------|------------|---------------------|--------|
| **Phase0 pass rate** | 98.1% (52/53) | **100% (61/61)** | +1.9% |
| **E2E pass rate** | 100% (6/6) | **100% (5/5)** | → |
| **P0 bugs** | 3 | **0** | -3 |
| **P1 gaps** | 5 (4 unresolved) | **1 (|| true deferred)** | -3 resolved |
| \|\| true instances | 174 | 175 | +1 |
| 2>/dev/null instances | 711 | 735 | +24* |
| mktemp without trap | 0 | 0 | → |
| CI pass rate (upstream) | 0% (5/5 failed) | **100% (success)** | +100% |
| Assertion hits | 930 | 970 | +40 |
| Test files | 122 | 130 | +8 |
| Lib test coverage | 0 lines | 355 lines | +∞ |

> * 2>/dev/null increase (+24) is almost entirely from new test files (test-lib-env.sh, test-lib-telegram.sh) which use `2>/dev/null` in legitimate mock setup patterns — not the silent-failure antipattern. The one antipattern instance (lib-telegram.sh python3) was REMOVED (-1).

## Key Improvements

### Structural
- **P0-BUG-01 fixed**: Orphan checksum cascade eliminated. `__pycache__/` added to never_touch in both checksums.yaml and generate-checksums.sh. Prevents recurrence.
- **P0-ANTI-01 fixed**: All 4 subprocess calls in run-e2e-ai.sh now capture stderr to log files. Errors displayed with full context. Logs retained on failure.
- **BATS integrated**: roles/synchronizer/tests/ now runs automatically in phase0 suite via run-phase0.sh.

### Coverage
- **+355 lines of new test code**: test-lib-env.sh (169L, 30 checks), test-lib-telegram.sh (185L, 28 checks)
- **+40 assertion hits**: from 930 to 970
- **+8 test files**: from 122 to 130

### Quality
- **canary-wp-gate.sh**: 3 `|| true` replaced with explicit `{ _fail; exit 1 }` guards
- **lib-telegram.sh**: python3 stderr masking removed, py_rc check + diagnostic added

## Net Assessment

| Dimension | Score | Change |
|-----------|-------|--------|
| P0 coverage | 3.5/5 | ↗ (was 2, all blockers resolved) |
| P1 coverage | 2.5/5 | → (|| true trend still unresolved) |
| Structural quality | 3.5/5 | ↗ (stderr capture, strict mode, trap hygiene) |
| CI reliability | 3/5 | ↗ (was 1, now unblocked) |
| **Overall** | **3/5** | → (stable, quality improved within band) |

---

*Cross-reference: `.audit/fix-review-2026-05-12-r4.md`, `.audit/measurement-2026-05-12-r4.json`.*
