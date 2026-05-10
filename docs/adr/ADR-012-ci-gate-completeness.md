# ADR-012: CI gate completeness — all validate-template.yml jobs must be required

**Status:** Proposed
**Date:** 2026-05-10
**Deciders:** Solo (re-audit)
**Audit reference:** `.audit/audit-report-2026-05-10.md` — finding P0-CI-01

---

## Context

The re-audit of FMT-exocortex-template (2026-05-10) identified that `validate-template.yml` has 6 jobs but only 4 are required by branch protection:
- **Required:** markdownlint, yamllint, shellcheck, validate
- **Not required:** upgrade-test, integration-contract

The upgrade-test and integration-contract jobs have been failing for 5 consecutive runs (since 2026-05-09) with no detection. The audit finding states:

> CI has been silently broken for days without detection. This is the "Coverage as the Goal" antipattern: required checks pass, suggesting quality, while real structural issues go undetected.

The constraints on this decision:
- Must not break existing PR workflow.
- upgrade-test and integration-contract failures must be investigated before making blocking.
- Branch protection configuration is managed via GitHub API/UI, not in-repo config.

## Decision

**Add `upgrade-test` and `integration-contract` to branch protection required status checks for `main` branch.** Before making them blocking, investigate and fix the current failures:
1. `integration-contract`: smoke-test-fresh-install step fails (28 checks). Investigate and fix.
2. `upgrade-test`: Upgrade simulation step fails. Investigate and fix.
3. Once both pass consistently (3 consecutive runs), add to required contexts.

If either job cannot be fixed within 1 week, add as advisory (non-blocking) and create a separate issue to track.

## Alternatives considered

### Alternative A: Remove failing jobs
- **Approach:** Delete upgrade-test and integration-contract from the workflow since they fail.
- **Pro:** Immediate green CI.
- **Con:** Loses smoke-test-fresh-install coverage (28 checks) and upgrade simulation — both were added for a reason.
- **Why not chosen:** Removing tests because they fail is the wrong response to test failure. Fix the tests or fix the code they're testing.

### Alternative B: Keep failing jobs non-blocking, add monitoring
- **Approach:** Leave as-is but add a scheduled workflow that alerts on repeated failures.
- **Pro:** No impact on PR workflow.
- **Con:** Delays detection. The jobs have been failing for days already with no alert.
- **Why not chosen:** Monitoring is a useful supplement but not a replacement for blocking gates. The jobs exist to catch regressions — if they don't block, they don't catch.

### Alternative C: do nothing
- **Pro:** Zero implementation cost.
- **Con:** CI erosion continues. Failed upgrade and fresh-install tests mask potential regressions. Trust in CI diminishes.
- **Why not chosen:** P0 finding from audit requires action. Silent CI failures are actively misleading.

## Consequences

### Positive
- CI gate completeness: all 6 validate-template.yml jobs must pass before merge.
- Upgrade path regressions caught at PR time, not in production.
- Fresh-install smoke test (28 checks) becomes a blocking quality gate.

### Negative
- CI wall time for PR checks increases (currently 47s upgrade-test + 21s integration-contract).
- First-time fix of failing jobs requires investigation effort (estimated 1-2h for root cause + fix).
- If failures can't be fixed quickly, PRs will be blocked — needs fast follow-up.

### Neutral / future implications
- Future CI job additions should be added to branch protection simultaneously (not after-the-fact).
- Consider adding a CI job that verifies branch protection completeness (meta-gate).

## Implementation notes

- Configuration: GitHub branch protection settings for `main` branch (Settings → Branches → Branch protection rules).
- Fix first, then add to required: current failures must be resolved before blocking.
- Tracking: part of P0-CI-01 remediation in Week 1 milestone.
- Related: `references/ci-gates.md` — No-flake-merge gate pattern.

## Verification

- Metric: validate-template.yml pass rate
- Target: 100% (all 6 jobs pass on every PR)
- Verify: `gh run list --workflow validate-template.yml --limit 5 --json conclusion` shows all "success"
- Re-measurement: Phase 11 of current audit cycle

## References

- Audit report: `.audit/audit-report-2026-05-10.md#finding-P0-CI-01`
- Source: SWE@Google Ch.11 — CI gates must be comprehensive
- Related: `references/ci-gates.md` in test-suite-auditor skill
