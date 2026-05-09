# Implementation Plan: ADR-010

> **Status:** Ready for execution
> **Last updated:** 2026-05-09
> **ADR:** `docs/adr/ADR-010-wp-session-switching.md`
> **Project:** [ADR-010 WP session switching](https://github.com/users/abcdef0101/projects/13)
> **Branch:** `0.25.1`

---

## Initial State

| Artifact | Status |
|----------|--------|
| ADR-010 | Accepted |
| `/sessions` native OpenCode command | Exists, manual selection only |
| `/tui/select-session` OpenCode API | Available |
| Work-product protocol | Exists, but not connected to TUI session switching |
| `/wp` custom command | Not implemented |
| WP session plugin/tool | Not implemented |

---

## Dependencies and Order

```
M0 (Design/Scaffold) ──→ M1 (Resolver) ──→ M2 (TUI Integration) ──→ M3 (Verification/Docs)
```

M1 depends on the command/plugin scaffolding from M0. M2 depends on a working resolver from M1. M3 depends on all prior milestones.

---

## Milestones

### M0: Command and plugin scaffold

**Scope:** Create the OpenCode command entrypoint and plugin skeleton without final resolution logic.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #194 | Add `/wp` custom command scaffold | `enhancement`, `adr` |
| #194 | Add WP session plugin scaffold | `enhancement`, `adr` |

**Expected Artifacts:**

- `.opencode/commands/wp.md`
- `.opencode/plugins/wp-session.js`
- command/plugin loading documentation in repo context if required

**Verification:**

- OpenCode detects the `/wp` command
- OpenCode loads the plugin without startup errors

### M1: WP resolver and validation

**Scope:** Implement deterministic normalization, WP existence checks, and native session discovery/ranking.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #193 | Implement WP normalization and validation | `enhancement`, `adr` |
| #193 | Implement native session list ranking for WP matches | `enhancement`, `adr` |
| #193 | Implement ambiguity-safe failure path | `enhancement`, `adr` |

**Expected Artifacts:**

- normalization helper for `WP-N`
- MEMORY/WP-REGISTRY validation path
- session ranking logic based on title strictness

**Verification:**

- automated tests for normalization and ranking
- missing WP refuses to create/switch sessions
- multiple strong matches return ambiguity instead of guessing

### M2: Session creation and TUI switching

**Scope:** Wire the resolver to OpenCode create/select APIs for real in-client switching.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #196 | Create canonical WP session when none exists | `enhancement`, `adr` |
| #196 | Switch TUI via `tui.selectSession` | `enhancement`, `adr` |
| #196 | Add user-visible success/error messages | `enhancement`, `adr` |

**Expected Artifacts:**

- plugin uses `session.create` for empty-match flow
- plugin uses `tui.selectSession` for hot-switch flow
- canonical title creation: `WP-N: <title>`

**Verification:**

- existing matching session switches without TUI restart
- no-match flow creates then switches
- created sessions follow the canonical title convention

### M3: Verification and documentation

**Scope:** Add regression tests and document the workflow contract.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #195 | Add automated tests for `/wp` behavior | `enhancement`, `adr` |
| #195 | Document WP session naming and ambiguity rules | `enhancement`, `adr` |
| #195 | Record follow-up criteria for optional mapping ADR | `enhancement`, `adr` |

**Expected Artifacts:**

- tests covering success, create, ambiguity, and missing-WP flows
- documentation for `/wp` and canonical session titles
- note describing when explicit mapping becomes justified

**Verification:**

- test suite covers all four primary flows
- docs mention `WP-N: <title>` convention and ambiguity stop behavior

---

## Blockers & Risks

| Blocker/Risk | Impact | Mitigation |
|-------------|--------|------------|
| OpenCode plugin runtime differs from documented SDK surface | Could block direct `tui.selectSession` calls | Validate against installed SDK before implementation; add smoke test early in M0 |
| Session discovery by title is too ambiguous in real use | Users may not resume the intended session | Strict ranking + fail-safe ambiguity handling; follow up with explicit mapping only if needed |
| Legacy freeform session titles reduce match quality | More no-match or ambiguity cases | Canonical naming for all newly created sessions; keep legacy fallback low-priority |
| Workspace path assumptions differ across installs | WP validation may read the wrong files | Resolve paths through workspace conventions already used by the repo |

---

## Ready Gate Checklist

Before marking this plan as `Ready for execution`:

- [ ] ADR status: `Accepted`
- [ ] All milestones have defined issues
- [ ] Dependency order is correct
- [ ] No blocking unknowns
- [ ] archgate passed
- [ ] Migration reviewed: additive, no transcript migration required
- [ ] Security reviewed: ambiguity and wrong-session switching mitigated
- [ ] Verification strategy defined per milestone

---

## Exit Criteria

- [ ] `/wp <WP-id>` is available in OpenCode for this project
- [ ] Existing single-match sessions switch in-place via TUI
- [ ] Missing-match flow creates `WP-N: <title>` and switches to it
- [ ] Ambiguous matches fail safely without silent switching
- [ ] Missing WP refuses to create a session
- [ ] Tests cover normalize/match/create/switch/error flows
- [ ] ADR status: `Implemented`

---

## Summary

| Milestone | Status | Issues |
|-----------|--------|--------|
| M0: Command and plugin scaffold | Planned | #194 |
| M1: WP resolver and validation | Planned | #193 |
| M2: Session creation and TUI switching | Planned | #196 |
| M3: Verification and documentation | Planned | #195 |
