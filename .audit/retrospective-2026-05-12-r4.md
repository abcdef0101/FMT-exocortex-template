# Retrospective — Re-audit #4

**Date:** 2026-05-12
**Audits completed:** 4 (2026-05-07, 2026-05-10, 2026-05-12 × 2)

---

## What Worked

### Audit process
- **Re-audit cadence worked well.** The 2-day gap (May 10 → May 12) gave enough time for fixes to accumulate. Four audits since May 7 show the suite improving measurably.
- **Cross-referenced findings.** Each re-audit checked resolution status of previous findings. Found that 4/4 P0/P1 items from audit #3 were fixed.
- **Local verification before pushing.** Running phase0 + E2E locally prevented broken code from reaching CI again.
- **Failure Injection Gate caught a real issue.** P2-ANTI-01 was initially marked "minor, behavior correct" — the FI gate confirmed python3 crash produces diagnostic → validated.

### Technical fixes
- **stderr capture pattern** in run-e2e-ai.sh is now the model for all AI E2E subprocess calls. Logs retained on failure, cleaned on success.
- **never_touch list** expansion (adding __pycache__/) prevents recurrence of the entire P0-BUG class.
- **BATS integration** into phase0 runner makes the 6 BATS test files visible to CI and local runs.
- **355 lines of lib tests** close a previous P1 gap efficiently.

### Process
- **Solo-mode compression** was appropriate. Skipping GitHub project setup (Phase 6) and issues (Phase 7) avoided overhead for 5 findings.
- **Atomic commits by finding ID** made the fix chain traceable.

---

## What Didn't Work

### Audit process gaps
- **checksums.yaml follow-up**. Deleting `protocol-close.md.backup` created a new orphan — caught during Phase 10 fix-review. The batch of fixes should have included a `generate-checksums.sh` re-run.
- **Scope mismatch in metric collection**. || true / 2>/dev/null count scopes differed between baseline (excluded roles/) and re-measurement (included roles/). Fixed by re-measuring with matching scope, but cost time.
- **CI visibility gap**. Pushed to `0.25.1` but validate-template only runs on `main` — the push didn't trigger CI. Fixes aren't verified by CI until merged to main.

### Technical debt still unresolved
- **|| true growth** (16 → 174+ → 175). Rate slowed from explosive to trickle, but still upward. Needs a cap or a pre-commit gate.
- **TEST-COVERAGE.md staleness**. The coverage map is still at "23 tested scripts" from audit #1. New lib tests aren't reflected.

### Tooling limitations
- **No coverage tool for Bash**. Line/branch coverage, mutation score — all null. The TEST-COVERAGE.md manual map is the only proxy.
- **No ShellCheck locally**. Only runs in CI, making local pre-commit validation harder.

---

## What to Add to Next Iteration

### Immediate (next re-audit)
1. **Update TEST-COVERAGE.md** with new lib coverage and BATS tests.
2. **Set a || true / 2>/dev/null cap.** Proposal: no increase allowed. Any new instance needs a comment explaining why (like "advisory" in run-e2e-ai.sh).
3. **Add bash -n pre-commit hook.** CI already runs it, but local gate would catch syntax errors earlier.

### Medium-term
4. **Install ShellCheck locally.** `apt-get install shellcheck` — one command, high leverage.
5. **Expand TEST-COVERAGE.md to track all 80 production scripts.** Currently tracks 23. The rest are unaccounted for.
6. **Add canary test for || true / 2>/dev/null growth.** A script that counts these patterns and fails if counts exceed threshold.

### Long-term (if project grows)
7. **Consider bash coverage tooling.** `kcov` can profile bash scripts for line coverage. Low priority for a solo project.
8. **CI gate on test count decrease.** If a test file is removed without a PR comment, fail the build.

---

## Continuous Monitoring Recommendation

Since this is a solo project without mutation/coverage tools, the simplest effective monitoring:

### Weekly (automated)
- Run `bash scripts/test/run-phase0.sh` on cron (already in cloud-scheduler.yml)
- Add a check script: count || true and 2>/dev/null, warn if above threshold

### Per-release
- Re-run `bash scripts/generate-checksums.sh` and verify 0 orphans
- Re-run E2E suite

### Monthly
- Full re-audit using test-suite-auditor skill
- Cross-reference with previous findings
- Compare || true / 2>/dev/null trends

### File: `.audit/CONTINUOUS-AUDIT.md`

---

*Written: 2026-05-12. Next re-audit: ~2026-05-26 (biweekly) or on significant test infrastructure changes.*
