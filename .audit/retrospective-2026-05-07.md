# Retrospective — 2026-05-07

> Audit: `.audit/audit-report-2026-05-07.md`
> Based on 12-phase test-suite-auditor workflow (solo-adapted)

## What Worked

1. **Full workflow on bash-only project** — the skill adapts well to non-traditional stacks
2. **Previous audit as reference** — 2026-05-06 findings provided useful cross-check (M1 already fixed, C3/C4 fixed)
3. **set -euo pipefail deployment** — 10 files changed, zero regressions, 100% pass rate
4. **CI gates** — bash -n + ShellCheck in CI (PR #139) prevents regression
5. **gh CLI automation** — project, milestones, labels, 21 issues created in ~2 min
6. **Quick wins delivered** — pass rate 85.7%→100% in ~15 min of actual fixes

## What Didn't Work

1. **P0-BUG-01 over-diagnosed** — test-update-check.sh failure was simpler than initially thought (grep escape bug, not a deep structural issue)
2. **P1-GAP-01 false positive** — trap analysis was based on grep count, not actual mktemp usage. All mktemp-using files already had trap
3. **gh-sub-issue 404 errors** — linking issues via extension failed (possibly feature not enabled on repo). Manual linking needed
4. **Forked repo complexity** — ci/add-bash-syntax-gate branch had no common ancestor with origin/main. Required v2 branch from origin
5. **P0-GAP-01/02 deferred** — 542 untested lines remain. Requires dedicated session for test authoring

## What to Add Next Iteration

1. **Dedicated test writing session** — P0-GAP-01 (hooks) and P0-GAP-02 (ai-cli-wrapper) are the highest-value remaining gap
2. **ShellCheck local integration** — add to run-phase0.sh as optional step (skip if not installed)
3. **CONTINUOUS-AUDIT.md** — document the cadence: quarterly full audit, weekly metric check
4. **Scheduled re-measurement** — weekly GitHub Action that reruns test suite and opens issue on regression

## Lessons

| Lesson | Action |
|--------|--------|
| Bash tests need `set -euo pipefail` — 36% didn't have it | Enforced in CI + all test files now compliant |
| `|| true` is the "skip" of bash — 16 instances found | Replaced with [WARN] reporting |
| Test hermeticity needs active enforcement | P2-QUAL-04 identified workspace mutation |
| Version skew is a real failure mode — MANIFEST 0.28.0 vs 0.28.1 | test-manifest-files.sh caught it, now part of CI |
| Grep portability matters — GNU \| breaks on BSD | Fixed with grep -E |
