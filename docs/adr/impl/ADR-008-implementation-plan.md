# Implementation Plan: ADR-008

> **Status:** Planned
> **Last updated:** 2026-05-06
> **ADR:** `docs/adr/ADR-008-ai-provider-abstraction.md`
> **Project:** [FMT-exocortex-template](https://github.com/abcdef0101/FMT-exocortex-template/projects)
> **Branch:** 0.25.1

---

## Initial State

| Artifact | Status |
|----------|--------|
| ADR-008 | Proposed (this document) |
| Phase A (env vars) | **Done** — `c1e8ff9`, pushed, CI green |
| Phase B (wrapper) | `scripts/ai-cli-wrapper.sh` written, not integrated |
| Phase C (opencode agent) | Not started |
| Phase D (docs) | Not started |

---

## Dependencies and Order

```
M1 (Phase A) ✅ ──→ M2 (Phase B) ──→ M3 (Phase C) ──→ M4 (Phase D)
```

M2 blocks M3 (wrapper needed for agent-creation). M3 blocks M4 (docs describe final state). All milestones are independent of other ADRs.

---

## Milestones

### M1: Provider-agnostic env vars (Phase A) ✅ DONE

**Scope:** Rename `CLAUDE_PATH` → `AI_CLI_PATH` with backward-compatible fallbacks across 10 files.

**Status:** Done. Commit `c1e8ff9`.

**Expected Artifacts:**
- [x] `test-phases.sh` — `ANTHROPIC_API_KEY` → `AI_CLI_API_KEY`, `claude` → `$AI_CLI`
- [x] `test-container.yml` + `test-golden.yml` — `AI_CLI_API_KEY` secret
- [x] `strategist.sh` — `AI_CLI_PATH`, `AI_CLI_TIMEOUT`, `--ai-cli-path`
- [x] `strategist/install.sh` — same
- [x] `scheduler.sh` — auto-detect `claude || opencode`
- [x] `extractor/install.sh` — auto-detect `claude || opencode`
- [x] `packages-firstboot.sh` + `Containerfile` — `AI_CLI_PACKAGE` env override
- [x] `run-weekly.sh` — `AI_CLI_API_KEY` gate

**Verification:** Phase 5a passes (6/6). Container + VM CI green.

---

### M2: CLI Wrapper + Phase 5b Integration (Phase B)

**Scope:** Integrate `ai-cli-wrapper.sh` into Phase 5b and `strategist.sh`.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| 1 | Integrate ai-cli-wrapper.sh into test-phases.sh Phase 5b | `phase-b`, `testing` |
| 2 | Integrate ai-cli-wrapper.sh into strategist.sh run_claude() | `phase-b`, `roles` |
| 3 | Upload wrapper to container/VM in test runners | `phase-b`, `testing` |
| 4 | Handle log output differences between claude and opencode | `phase-b`, `testing` |

**Expected Artifacts:**
- `test-phases.sh` Phase 5b uses `ai_cli_run()` instead of `$AI_CLI --bare -p`
- `strategist.sh` `run_claude()` uses `ai_cli_run()` internally
- `test-from-container.sh` and `test-from-golden.sh` upload `ai-cli-wrapper.sh`
- OpenCode log output parsed correctly in `LOG_FILE`

**Verification:**
- Phase 5a unchanged (6/6)
- Phase 5b with `AI_CLI=claude` → same behavior as before
- `bash -n` on all modified scripts

---

### M3: OpenCode Agent Setup (Phase C)

**Scope:** Pre-create OpenCode agent for `--allowedTools` equivalent. Automate in verify/CI.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| 5 | Create opencode agent 'strategist-test' in verify-container.sh | `phase-c`, `ci` |
| 6 | Create opencode agent 'strategist-test' in verify-golden.sh | `phase-c`, `ci` |
| 7 | Add agent creation to CI workflow (test-container.yml) | `phase-c`, `ci` |
| 8 | Handle agent already-exists case (idempotency) | `phase-c`, `ci` |

**Expected Artifacts:**
- `verify-container.sh --full` creates `strategist-test` agent for opencode
- `verify-golden.sh --full` does the same
- CI `test-container.yml` creates agent before Phase 5b
- `ai_cli_agent_create()` in wrapper handles idempotency (exists → skip)

**Verification:**
- `opencod agent list | grep strategist-test` after verify
- Agent creation is no-op for claude (wrapper returns 0)
- CI workflow_dispatch with `AI_CLI=opencode` creates agent successfully

---

### M4: Documentation (Phase D)

**Scope:** Document OpenCode usage for IWE users.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| 9 | Document AI_CLI/AI_CLI_PATH env vars in SETUP-GUIDE.md | `phase-d`, `docs` |
| 10 | Document opencode AGENTS.md equivalent of CLAUDE.md | `phase-d`, `docs` |
| 11 | Add opencode provider example to params.yaml | `phase-d`, `config` |
| 12 | Update CHANGELOG.md with ADR-008 entry | `phase-d`, `docs` |

**Expected Artifacts:**
- `docs/SETUP-GUIDE.md` — section «Выбор AI-провайдера» with `AI_CLI=opencode` example
- `docs/IWE-HELP.md` — troubleshooting for provider switch
- `seed/params.yaml` — commented example: `# AI_CLI: opencode  # альтернатива: claude`
- `CHANGELOG.md` — ADR-008 entry

**Verification:**
- Docs grep: `AI_CLI` found in SETUP-GUIDE.md, IWE-HELP.md
- `grep "AI_CLI" seed/params.yaml` returns commented example
- CHANGELOG references ADR-008

---

## Blockers & Risks

| Blocker/Risk | Impact | Mitigation |
|-------------|--------|------------|
| OpenCode `--pure` ≠ Claude `--bare` semantics | Phase 5b may load different context | Document difference; accept as acceptable variance |
| Wrapper breaks Claude path (regression) | Existing users affected | Phase 5b test with `AI_CLI=claude` in CI before merge |
| OpenCode agent creation fails in CI (no PTY) | M3 blocked | `script -qc` wrapper used elsewhere in test-phases.sh |
| `CLAUDE.md` vs `AGENTS.md` confusion | Users unsure which to edit | Phase D documents: use both, Claude reads CLAUDE.md, OpenCode reads AGENTS.md |

## Ready Gate Checklist

Before marking this plan as `Ready for execution`:

- [ ] ADR status: `Accepted`
- [ ] All milestones have defined issues
- [ ] Dependency order is correct
- [ ] No blocking unknowns
- [ ] archgate passed
- [ ] Migration reviewed: Phase A done, backward compat verified
- [ ] Security reviewed: no new PII/tokens/secrets introduced

---

## Exit Criteria

- [ ] All milestones M2-M4 implemented
- [ ] All execution issues (#1-#12) closed
- [ ] ADR status: `Implemented`
- [ ] CHANGELOG updated
- [ ] Both providers pass Phase 5a (6/6)
- [ ] `AI_CLI=claude` passes Phase 5b headless E2E
- [ ] `AI_CLI=opencode` passes Phase 5b headless E2E (or gracefully skips)

---

## Summary

| Milestone | Status | Issues |
|-----------|--------|--------|
| M1: Env vars (Phase A) | ✅ Done | `c1e8ff9` |
| M2: Wrapper (Phase B) | Planned | #1-#4 |
| M3: Agent setup (Phase C) | Planned | #5-#8 |
| M4: Docs (Phase D) | Planned | #9-#12 |
