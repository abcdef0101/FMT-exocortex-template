# Retrospective — Test Suite Audit 2026-05-12

## What went well

- **Trap hygiene fully resolved.** 0 mktemp without trap — the fix from 2026-05-10 audit held and expanded to all new files.
- **Strict mode 100% maintained.** Every new file added since last audit includes `set -euo pipefail`.
- **E2E suite healthy.** 6/6 pass, expanded by 1 scenario (extractor offline fallback).
- **test-checksums.sh hermetic fix is correct.** The copy/restore pattern works — only the data (checksums.yaml) has a stale entry.
- **BATS adoption is structured.** Proper test separation (adapters, integration, lib, notify, scripts, templates).

## What went wrong

- **CI regressed from partial to total failure.** Expanding CI to run full phase0 without first fixing the phase0 failure created a broader blockage. The right sequence would have been: fix tests → expand CI.
- **|| true continued to grow (+18).** Copy-paste adoption of the pattern in new files. Needs a pre-commit hook to block new instances.
- **New production code added without tests.** lib/ directory arrived without corresponding test files. Testing lagged behind development velocity (18 commits in 2 days).

## Key lessons

1. **Fix before expand.** Expanding CI test coverage without fixing existing failures is net-negative — it creates alarm fatigue.
2. **Test gates for test code.** The || true explosion would be caught by a CI lint check: `grep -c '|| true' scripts/test/*.sh` with a threshold.
3. **Checksums.yaml needs a pre-commit validation.** The orphan __pycache__ entry would be caught by a `git diff --check` on checksums regeneration.
4. **Templates need linting.** The `|| true` after `_fail` pattern (test-checksums.sh:54,127) survives because there's no lint rule against `_fail.*|| true`.

## What to add to next iteration

1. **Pre-commit hook: block new || true in test scripts** — only allow in specific patterns (trap cleanup, unset guard).
2. **Pre-commit hook: validate checksums.yaml** — no orphan entries, no pycache, no gitignored files.
3. **CI: diff-based gate** — block PRs that decrease test pass rate or increase || true count.
4. **Weekly automated metrics** — re-run baseline measurement weekly, open issue if phase0 pass rate <98%.

## DoD — next audit

| Metric | 2026-05-12 | Target (next audit) |
|--------|:----------:|:-------------------:|
| Phase0 pass rate | 98.1% | 100% |
| CI pass rate | 0% | 100% |
| || true (legitimate) | 174 (0) | <40 (classified) |
| 2>/dev/null in tests | 711 | <200 |
| BATS in CI | no | yes |
| lib/ test coverage | 0% | 100% |
