# Test Suite Audit Report — FMT-exocortex-template (Re-audit)

**Date:** 2026-05-10
**Auditor:** Claude (test-suite-auditor skill)
**Previous audit:** 2026-05-07 (`.audit/audit-report-2026-05-07.md`)
**Scope:** All `.sh` scripts under `scripts/test/`, `.claude/hooks/`, `.claude/scripts/`, `.claude/skills/`, `scripts/vm/`, `scripts/container/`, `scripts/lib/`, plus CI workflows under `.github/workflows/`. Excluded: `workspaces/` (gitignored user data).

---

## TL;DR

**Maturity:** **3** / 5 — massive test expansion (+318%, 28→117 files) brought structural antipatterns: || true explosion (16→156), gap in temp file cleanup (0→18 untrapped mktemp), and CI silently failing. Strict mode (100%) and core fixes from previous audit are preserved.

**Top three problems:**

1. **CI validate-template.yml failing 5/5 runs but failing jobs NOT blocking** — upgrade-test and integration-contract fail silently; only 4/6 jobs are required by branch protection.
2. **test-checksums.sh mutates production checksums.yaml** — calls generate-checksums.sh which writes to $ROOT_DIR/checksums.yaml, causing order-dependent failures in the phase0 runner.
3. **156 || true instances across 117 test files** — 9.75x regression since previous audit, masks command failures in assertions, seed scripts, and canary health checks.

The test suite grew from 28 to 117 files with strong improvements (100% strict mode, 98% phase0 pass rate, test-hooks.sh addressing previous Beyoncé Rule gap). However, the growth introduced copy-paste antipatterns. The priority this sprint: fix CI gates, fix checksums mutation, and begin systematic || true reduction.

**Maturity rubric reference:**
- **1** — No automated tests, or tests don't run reliably in CI.
- **2** — Tests exist but quality is uneven; suite is slow or flaky enough that the team works around it.
- **3** — Tests are reliable but provide weak signal: high coverage, low confidence; over-mocked or implementation-coupled.
- **4** — Tests genuinely verify behavior, suite is fast, flake is managed. A few SOTA practices missing.
- **5** — Mature suite: behavior-driven, hermetic, multiple test types in appropriate proportions, mutation/property-based testing where it pays off, contract tests at boundaries.

---

## Inventory

### Stack

| Aspect | Value |
|---|---|
| Language / runtime | Bash 5 |
| Config formats | YAML, JSON, Markdown |
| Test frameworks | Custom (_pass/_fail functions) |
| Mocking / fixtures | Temp directories (mktemp), git worktrees |
| Coverage tool | _not present_ |
| Mutation tool | _not present_ |
| Property-based testing | _not present_ |
| Contract testing | _not present_ |
| Integration testing | E2E scripts (setup.sh cycles), container/VM golden images |
| CI runner | GitHub Actions |
| CI test runtime | shellcheck: 13s, validate: 3s, upgrade-test: 47s, integration-contract: 21s |

### Suite distribution

| Layer | Count | % | Avg runtime | Notes |
|---|---|---|---|---|
| Unit (test-*.sh) | 51 | 43.6% | <1s each | 50/51 pass (98%), 831 total assertions |
| Assert (assert-*.sh) | 18 | 15.4% | not measured | LLM-as-Judge structural invariants, requires API keys |
| Eval (eval-*.sh) | 17 | 14.5% | not measured | LLM evaluation scripts, requires API keys |
| Seed (seed-*.sh) | 17 | 14.5% | not measured | AI smoke test data generators |
| Canary (canary-*.sh) | 5 | 4.3% | not measured | Weekly health checks, requires API keys |
| E2E (e2e-*.sh) | 5 | 4.3% | ~30s each | 5/5 pass (100%), setup.sh lifecycle tests |
| Runners + libs | 4 | 3.4% | — | run-phase0.sh, run-e2e.sh, run-e2e-ai.sh, _lib.sh |
| **Total** | **117** | 100% | — | |

**Observed shape:** Hybrid — unit tests dominate (44%) + heavy AI smoke layer (44% combined assert/eval/seed). E2E is appropriately thin (4%). This resembles the Testing Trophy shape (thick integration layer) but the AI smoke tests are a novel pattern.

**Architecture-appropriate shape:** For a Bash project, the shape is appropriate. The AI smoke layer is not standard in any pyramid/trophy/honeycomb model — it's an innovation worth documenting but not a mismatch.

**Mismatch?** No. The distribution is intentional (ADR-009 — 3-layer IWE behavior validation).

### Metrics snapshot

| Metric | Baseline 2026-05-10 | Previous 2026-05-07 | Target |
|---|---|---|---|
| Phase0 pass rate | 98% (50/51) | 85.7% (12/14) | 100% |
| E2E pass rate | 100% (5/5) | 100% (5/5) | 100% |
| Strict mode adherence | **100% (117/117)** | 64% (18/28) | 100% ✅ |
| || true instances | **156** | 16 | <20 legitimate |
| mktemp without trap | **18** | 0 (false positive) | 0 |
| Untested prod scripts | **26/32 (81%)** | 9/22 (41%) | 0 |
| CI pass rate (validate) | **0% (0/5)** | not measured | 100% |
| ShellCheck local | not installed | not installed | installed |

---

## Findings

### P0 — actively misleading or hiding bugs

#### P0-BUG-01: test-checksums.sh mutates production checksums.yaml

- **What:** The test calls `generate-checksums.sh` which writes directly to `$ROOT_DIR/checksums.yaml` — the production file. This non-hermetic mutation causes order-dependent failures in the phase0 runner.
- **Evidence:** `scripts/test/test-checksums.sh:19` — `bash "$GEN_SCRIPT"` regenerates actual checksums.yaml on disk. `scripts/generate-checksums.sh:10` — `OUTPUT="$ROOT_DIR/checksums.yaml"`. After regeneration: 70 insertions, 5 deletions from committed version. Runner output: "key file missing: CLAUDE.md (in files section)".
- **Why it harms:** The test modifies shared production state. Subsequent test runs operate on the mutated checksums.yaml. This is the Shared Mutable State antipattern (Luo et al. 2014). The phase0 runner fails on this test because the freshly-generated checksums.yaml has entries in a format that the key-file grep doesn't match when run through the runner context.
- **Source:** SWE@Google Ch.11 — hermetic tests; Shared Mutable State antipattern (Luo et al. 2014; Romano et al. ICSE 2021)
- **Recommended fix:** (1) Regenerate checksums.yaml to `/tmp` instead of `$ROOT_DIR`. (2) Copy relevant production state to temp dir, run generator there. (3) Add trap cleanup for temp files. (4) Verify test passes in both isolation AND full suite.
- **Effort:** M

#### P0-GAP-01: 26 untested production scripts — Beyoncé Rule

- **What:** The gap expanded from 9 scripts (542 lines) in the previous audit to 26 scripts. New production code (VM pipeline, container tooling, skill scripts) was added without corresponding tests.
- **Evidence:** `.claude/hooks/` — 7 scripts (381 lines) untested. `.claude/scripts/` — 2 scripts (161 lines) with only syntax checks. `.claude/skills/` — 4 scripts untested. `scripts/vm/` — 10 scripts untested. `scripts/container/` — 3 scripts untested. `scripts/lib/manifest-lib.sh` — untested.
- **Why it harms:** The Beyoncé Rule states: any production behavior the team relies on must be guarded by an automated test. These scripts gate AI session lifecycle, workspace resolution, VM image builds, and container operations — all critical infrastructure. Previous audit P0-GAP-01 identified the same gap; test-hooks.sh was added but only covers syntax/structure, not behavior.
- **Source:** SWE@Google Ch.11 — Beyoncé Rule: "If you liked it, you should have put a CI test on it"
- **Recommended fix:** Phase 1: Verify test-hooks.sh coverage is complete. Phase 2: Add behavioral tests for resolve-workspace.sh and load-extensions.sh. Phase 3: Add test-manifest-lib.sh. Phase 4: VM/container scripts require QEMU/Podman — document testing constraints.
- **Effort:** L

#### P0-CI-01: CI silently failing — 5/5 runs, failing jobs not blocking

- **What:** validate-template.yml has failed 5 consecutive runs (since 2026-05-09). The upgrade-test and integration-contract jobs fail consistently, but branch protection only requires 4 other jobs (markdownlint, yamllint, shellcheck, validate).
- **Evidence:** Branch protection contexts: `["markdownlint","yamllint","shellcheck","validate"]` — missing `upgrade-test` and `integration-contract`. Integration-contract job: `smoke-test-fresh-install` step fails with 28 checks. upgrade-test: `Upgrade simulation` step fails.
- **Why it harms:** Failing jobs are silently ignored — PRs merge despite broken upgrade simulation and fresh-install smoke tests. This is the "Coverage as the Goal" antipattern applied to CI: required checks pass (suggesting quality) while real structural issues go undetected. CI has been silently broken for days.
- **Source:** SWE@Google Ch.11 — tests must report failures accurately; CI gates must be comprehensive
- **Recommended fix:** (1) Add `upgrade-test` and `integration-contract` to branch protection required contexts. (2) Investigate and fix smoke-test-fresh-install failure. (3) Investigate upgrade-test failure. (4) Run validate-template.yml locally before committing changes.
- **Effort:** M

#### P0-ANTI-01: E2E AI runner masks ALL error output with 2>/dev/null

- **What:** The E2E AI runner (`run-e2e-ai.sh`) passes every subprocess through `2>/dev/null`, masking all stderr from seed, eval, assert, and symlink operations across 16 AI workflows.
- **Evidence:** `scripts/test/e2e/run-e2e-ai.sh:21` — `WS=$(bash "$seed" 2>/dev/null | tail -1)` — seed stderr hidden. `:27` — `ln -sfn . "$WS/DS-strategy" 2>/dev/null || true` — symlink failure masked. `:35,46,59` — run, judge, assert all through `2>/dev/null`.
- **Why it harms:** If a seed script crashes with a bash error, stderr is hidden — only the last stdout line is captured. If eval encounters a Python/JSON parse error, it's hidden. This is the Command Substitution Without Exit Check antipattern at the orchestrator level. Any failure in any of 16 AI E2E workflows can produce a false PASS.
- **Source:** Failure-mode antipattern: Command substitution without exit check (bash manual §Shell Builtin Commands); Auto-retry as Flake Mitigation antipattern (Google Testing Blog)
- **Recommended fix:** (1) Capture stderr to temp files alongside stdout, display on failure. (2) Replace `2>/dev/null || true` on symlink with explicit error check. (3) Add non-zero exit code check with clear error message for each stage. (4) Log all output to structured directory for post-mortem.
- **Effort:** M

---

### P1 — significantly slows the team or erodes confidence

#### P1-ANTI-02: 156 || true instances — 9.75x regression

- **What:** The || true pattern exploded from 16 to 156 instances across all 117 test files. Top offenders: test-extension-points.sh (8), test-ai-cli-wrapper.sh (8), canary-wp-gate.sh (6).
- **Evidence:** `scripts/test/test-extension-points.sh:18,36,56,73,78,129,134,159` — masks grep failures. `scripts/test/test-ai-cli-wrapper.sh:38,68,100,106,111,112,160,169` — masks unset/detect failures. `scripts/test/canary-wp-gate.sh:58-60` — masks git init/add/commit failures. 156 total vs 16 in previous baseline.
- **Why it harms:** The Auto-retry as Flake Mitigation antipattern: when a command fails, the test continues rather than detecting the failure. In canary-wp-gate.sh, git init/add/commit are masked — if git is unavailable or disk full, the canary reports HEALTHY. The explosion suggests copy-paste adoption rather than deliberate choice.
- **Source:** Auto-retry as Flake Mitigation antipattern (Google Testing Blog, ICSE 2024 FTW workshop); SWE@Google Ch.11
- **Recommended fix:** Audit all 156 instances: classify as legitimate-fallback, error-masking, or cleanup-masking. Replace legit with pre-checks. Replace error-masking with explicit failure reporting. Replace cleanup-masking with trap EXIT. Target: reduce to <20 legitimate instances.
- **Effort:** L

#### P1-GAP-01: 18 mktemp without trap

- **What:** 14 seed scripts and 3 E2E scripts use mktemp but lack trap EXIT for cleanup.
- **Evidence:** `scripts/test/seed-day-close.sh, seed-integration-gate-e2e.sh, seed-quick-close.sh, seed-synchronizer-code-scan.sh, seed-skill-invocation-e2e.sh, seed-wp-gate-e2e.sh, seed-verifier-pack-entity.sh, seed-extractor-inbox-check.sh, seed-archgate-e2e.sh, seed-orz-cycle.sh, seed-note-review.sh, seed-week-close.sh, seed-session-prep.sh, seed-wp-new.sh, seed-role-execution-e2e.sh` — all mktemp, no trap. `scripts/test/e2e/e2e-migration.sh, e2e-update-flow.sh, e2e-fresh-install.sh` — mktemp, no trap.
- **Why it harms:** Without trap EXIT, temp directories accumulate in /tmp. On systems with limited /tmp space, this causes flaky failures when mktemp can't allocate. Previous audit flagged this as false-positive (0 instances); now 18 new files introduced the gap.
- **Source:** Shared Mutable State antipattern (Luo et al. 2014; Romano et al. ICSE 2021); SWE@Google Ch.11
- **Recommended fix:** Add `trap "rm -rf \"\$TMPDIR\"" EXIT` after every mktemp call in all 18 files. Consolidate multiple temp dirs into a single cleanup function.
- **Effort:** M

*(Remaining P1/P2 findings summarized — full details in `.audit/findings-2026-05-10.json`)*

#### P1-BUG-01: test-checksums.sh order-dependent failure
- Sub-finding of P0-BUG-01. Same root cause: checksums mutation.
- **Effort:** M

#### P1-GAP-02: Canary scripts mask git failures with || true
- **Evidence:** `scripts/test/canary-wp-gate.sh:58-60`
- **Effort:** S

#### P1-GAP-03: ShellCheck absent from local dev loop
- Unchanged from previous audit. CI has it, local doesn't.
- **Effort:** S

#### P1-BUG-02: test-update-check.sh still references real update.sh
- Deferred from previous audit. Partially refactored.
- **Effort:** M

---

### P2 — quality, hygiene, future-proofing

| ID | Title | Evidence | Effort |
|----|-------|----------|--------|
| P2-QUAL-01 | Command substitution lacks exit checks | `test-migrations.sh:83`, `test-manifest-parser.sh:147` | M |
| P2-QUAL-02 | E2E AI runner has no trap cleanup | `run-e2e-ai.sh` (148 lines, no trap) | S |
| P2-QUAL-03 | run-phase0.sh grep filter hides failures | `run-phase0.sh:66` (known from prev audit) | S |
| P2-QUAL-04 | test-ai-cli-wrapper.sh unset -f || true may leak | `test-ai-cli-wrapper.sh:38,111-112` | S |
| P2-QUAL-05 | test-hooks.sh covers syntax not behavior | `test-hooks.sh:20-35` — Trivial Tests antipattern | M |
| P2-QUAL-06 | Canary API key loading duplicated 5x | `canary-*.sh:8-12` | S |
| P2-QUAL-07 | No coverage map (prod→test) | TEST-COVERAGE.md describes how-to-run, not what-is-covered | S |

---

## Strengths

- **100% strict mode adherence** (117/117 test files with `set -euo pipefail`) — up from 64% in previous audit. The previous audit's largest win has held and expanded.
- **test-hooks.sh** addresses the previous P0-GAP-01 (9 untested hooks) with syntax and structure validation — partial but real progress.
- **E2E test suite is 100% green** (5/5 pass) and covers the full setup.sh lifecycle (fresh install, author sync, conflict, migration, update flow).
- **3-layer testing strategy** (ADR-009) — assert/canary/eval/seed architecture with LLM-as-Judge is a novel and well-structured approach for AI behavior validation.
- **98% phase0 pass rate** — only 1 failure out of 51 tests, and the root cause is identified (P0-BUG-01, non-hermetic checksums generation).
- **831 assertions** across 51 unit test files — substantial assertion density.

---

## White spots

- **No behavioral tests for hooks.** test-hooks.sh checks syntax and JSON output format but not whether `protocol-stop-gate.sh` actually blocks when it should.
- **VM pipeline completely untested.** 10 scripts for QEMU/KVM golden image builds, provisioning, and verification — zero test coverage. Relies on CI golden-image workflow which is self-hosted and not part of standard PR checks.
- **Container pipeline untested.** 3 scripts (build, test-from-container, verify-container) — covered by self-hosted CI runner but not locally testable.
- **manifest-lib.sh untested.** Shared library used by setup.sh and manifest-parser. No dedicated test file.
- **resolve-workspace.sh untested.** Central workspace resolution logic (97 lines) — no behavioral tests, only bash -n in test-hooks.sh.
- **load-extensions.sh partially tested.** Syntax and help-checked in test-hooks.sh:184-205, but extension loading logic not behaviorally verified.
- **Canary scripts depend on live LLM calls.** No offline/mock mode for canary health checks — they require API keys and make real AI calls.
- **No mutation testing.** Standard for Bash: no tool exists. Acknowledge as a limitation, not a gap.
- **No coverage measurement.** No code coverage tool for Bash. Use production-script-to-test-file mapping as proxy.

---

## Roadmap

### Week 1 — Quick Wins (S/M effort)

1. **Fix P0-BUG-01: test-checksums.sh hermeticy** (M) — Regenerate checksums.yaml to temp dir instead of production. Fixes the last phase0 failure. *Addresses P0-BUG-01, P1-BUG-01.*
2. **Fix P0-CI-01: Add failing jobs to branch protection** (M) — Add upgrade-test and integration-contract to required contexts. Investigate and fix the failures. *Addresses P0-CI-01.*
3. **Fix P1-GAP-02: canary git failure masking** (S) — Replace || true with error handling in canary-wp-gate.sh and propagate to all 5 canary scripts. *Addresses P1-GAP-02, starts addressing P1-ANTI-02.*
4. **Fix P1-GAP-03: ShellCheck in local dev** (S) — Add ShellCheck installation check and default blocking mode to run-phase0.sh. *Addresses P1-GAP-03.*
5. **Fix P2-QUAL-02: trap in E2E AI runner** (S) — Add trap EXIT to run-e2e-ai.sh. *Addresses P2-QUAL-02.*

### Week 2 — Structural Fixes (M/L effort)

1. **Fix P0-ANTI-01: E2E AI runner error masking** (M) — Capture stderr to temp files, display on failure. Replace 2>/dev/null on seed/eval/assert calls. *Addresses P0-ANTI-01.*
2. **Reduce || true instances** (L) — Systematic audit of 156 instances. Classify and fix: replace error-masking with explicit checks, cleanup-masking with trap. Target: <20 legitimate. *Addresses P1-ANTI-02.*
3. **Fix P1-GAP-01: trap in 18 mktemp files** (M) — Add trap EXIT to all 18 seed/E2E scripts. *Addresses P1-GAP-01.*
4. **Fix P1-BUG-02: mock update.sh in test-update-check** (M) — Deferred from previous audit. Extract testable functions. *Addresses P1-BUG-02.*

### Week 3–4 — Investments (L effort)

1. **Address P0-GAP-01: production script test coverage** (L) — Phase 1: complete test-hooks.sh behavioral scenarios. Phase 2: test resolve-workspace.sh, load-extensions.sh. Phase 3: test manifest-lib.sh. Phase 4: document VM/container testing constraints.
2. **Fix P2-QUAL-05: behavioral tests for hooks** (M) — Add scenarios: protocol-stop-gate blocks when it should, artifact-validate catches broken artifacts.
3. **Fix P2-QUAL-01: command substitution exit checks** (M) — Standardize rc capture pattern across test layer.
4. **Fix P2-QUAL-06: canary API key deduplication** (S) — Extract shared env loading to _lib-auth.sh.

### Backlog (no dated commitment)

- P2-QUAL-03: run-phase0.sh grep filter
- P2-QUAL-04: test-ai-cli-wrapper.sh unset cleanup
- P2-QUAL-07: coverage map documentation

---

## Definition of Done (numerical exit criteria)

| Metric | Current | Target | How verified |
|--------|:------:|:------:|-------------|
| Phase0 pass rate | 98% (50/51) | **100% (no failures)** | `run-phase0.sh` exit 0 |
| E2E pass rate | 100% (5/5) | 100% (no regression) | `run-e2e.sh` exit 0 |
| CI pass rate (validate) | 0% (0/5) | **100% (all 6 jobs)** | Check branch protection + last 5 runs |
| || true instances (legitimate) | 156 (0 legit) | <20 legitimate (classified) | grep count after remediation |
| mktemp without trap | 18 | **0** | grep -L trap on mktemp files |
| Strict mode adherence | 100% (117/117) | 100% (no regression) | grep in all test files |
| E2E AI runner stderr capture | 0% captured | **100% captured** | stderr goes to temp file per stage |
| Canary git operations | masked (|| true) | **verified (exit check)** | grep for git.*\|\| true |

---

## Sources cited

- Software Engineering at Google, Ch. 11–12 — https://abseil.io/resources/swe-book/html/toc.html
- Martin Fowler — Test Pyramid: https://martinfowler.com/bliki/TestPyramid.html
- Kent C. Dodds — Testing Trophy: https://kentcdodds.com/blog/write-tests
- Meszaros — xUnit Test Patterns (Assertion Roulette antipattern)
- Khorikov — Unit Testing Principles (Structural Inspection, Pseudo-tested methods)
- Kapelonis — Software Testing Antipatterns catalog
- Luo et al. (2014) — Flaky test taxonomy (Order-Dependent Tests, Shared Mutable State)
- Romano et al. (ICSE 2021) — Flaky test research
- Google Testing Blog — Flaky tests series (Auto-retry, Sleeps as Synchronization)
- Testcontainers — https://testcontainers.com/guides/introducing-testcontainers/
- bash manual — §Shell Builtin Commands (command substitution exit propagation)
- Previous audit: `.audit/audit-report-2026-05-07.md`

---

## Open questions / unknowns

- **Integration-contract failure root cause:** The smoke-test-fresh-install step fails — what specifically is broken? Investigate before fixing P0-CI-01.
- **Upgrade-test failure root cause:** What fails in the upgrade simulation? Investigate before fixing P0-CI-01.
- **AI smoke tests pass rate:** The 17 eval + 17 seed scripts were not run (require LLM API keys). Their quality and pass rate are unknown.
- **Flake rate:** Not measured for any layer. No retry mechanism in CI, so no flake data available. Recommend collecting before next audit.
- **VM/container test quality:** Self-hosted runners are not accessible for local audit. Golden-image and container tests are assumed to work (CI shows no failures for these workflows).
- **ShellCheck warnings count:** ShellCheck runs in CI but the number of existing warnings is unknown. Run ShellCheck locally to establish baseline.
