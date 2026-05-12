# Continuous Audit — FMT-exocortex-template

> Cadence and monitoring for test suite health. Companion to `TEST-COVERAGE.md`.

## Cadence

| Frequency | What | Trigger |
|-----------|------|---------|
| **Per PR** | `bash -n` + ShellCheck on changed `.sh` files | CI (`validate-template.yml`) |
| **Weekly** | `run-phase0.sh` full suite | CI (`cloud-scheduler.yml`) |
| **Weekly** | || true / 2>/dev/null count check (advisory) | Manual or CI |
| **Monthly** | Full re-audit (test-suite-auditor skill) | Manual |
| **Post-incident** | Immediate targeted audit of affected area | Always |

## Metrics to Track

| Metric | Current (2026-05-12 R4) | Warning Threshold | Action |
|--------|------------------------|-------------------|--------|
| Phase0 pass rate | 100% (61/61) | < 100% | Block new PRs |
| E2E pass rate | 100% (5/5) | < 100% | Investigate immediately |
| \|\| true count | 175 | > 180 | Audit new instances |
| 2>/dev/null count | 735 | > 750 | Audit new instances |
| Test file count | 130 | < 128 | Validate no regression |
| mktemp without trap | 0 | > 0 | P0 — fix immediately |
| Orphan checksums | 0 | > 0 | P0 — fix immediately |

## Audit History

| Date | Audit # | Maturity | P0 | P1 | Key outcome |
|------|---------|----------|----|----|-------------|
| 2026-05-07 | #1 | 2 | 3 | 5 | Initial audit, strict mode 64% |
| 2026-05-10 | #2 | 2.5 | 3 | 5 | Strict mode → 100% (test files) |
| 2026-05-12 | #3 | 3 | 3 | 5 | mktemp hygiene fixed, CI regressed |
| 2026-05-12 | #4 | 3 | 0 | 1 | All P0/P1 fixed, BATS integrated, +355 lines |

## Last Audit

`.audit/audit-report-2026-05-12-r4.md`
