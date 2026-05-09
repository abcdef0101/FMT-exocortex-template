# Implementation Plan: ADR-011

> **Status:** Ready for execution
> **Last updated:** 2026-05-09
> **ADR:** `docs/adr/ADR-011-wp-new-session-handoff.md`
> **Project:** TBD
> **Branch:** `0.25.1`

---

## Initial State

| Artifact | Status |
|----------|--------|
| ADR-011 | Proposed |
| Service Clause SC-LOCAL-001 | Draft |
| `wp-new` workflow | Creates work products only |
| ADR-010 session resolver | Implemented for explicit `/wp WP-N` flow |
| Automatic `wp-new -> session handoff` | Not implemented |

---

## Dependencies and Order

```
M0 (Design alignment) ──→ M1 (Workflow integration) ──→ M2 (Session policy enforcement) ──→ M3 (Verification + docs)
```

M1 depends on ADR-011 acceptance and a stable understanding of the target model from ADR-011. M2 depends on M1 because side/main session behavior only matters once `wp-new` actually triggers handoff. M3 depends on all previous milestones.

---

## Milestones

### M0: Design alignment

**Scope:** Finalize the workflow contract between `wp-new` and the ADR-010 resolver.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #66 | Finalize `wp-new` post-create handoff contract | `enhancement` |
| #68 | Decide mandatory vs best-effort handoff semantics | `enhancement` |

**Expected Artifacts:**

- final ADR-011 status and tracked decisions
- UX contract for success / blocked / failed handoff

**Verification:**

- no unresolved workflow ambiguity in ADR text
- explicit decision recorded for failure isolation

### M1: Workflow integration

**Scope:** Extend `wp-new` so successful work-product creation triggers session handoff.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #62 | Emit `WP-N` + title from `wp-new` into handoff step | `enhancement` |
| #63 | Preserve successful WP creation when handoff fails | `enhancement` |

**Expected Artifacts:**

- updated `wp-new` workflow
- explicit call path into session handoff mechanism
- user-visible output for creation + switch status

**Verification:**

- successful WP creation triggers handoff
- handoff failure does not roll back planning artifacts

### M2: Session policy enforcement

**Scope:** Enforce the main/side session target model in the handoff path.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #67 | Prefer canonical main session over side sessions | `enhancement` |
| #65 | Define ambiguity behavior when multiple main candidates exist | `enhancement` |
| #64 | Define reopen behavior for newly reactivated work products | `enhancement` |

**Expected Artifacts:**

- main-session preference logic applied in `wp-new` handoff path
- no accidental selection of side sessions during automatic handoff
- explicit ambiguity UX

**Verification:**

- existing side session does not steal auto-handoff from main session
- ambiguous main candidates stop safely

### M3: Verification and documentation

**Scope:** Add regression coverage and document the integrated workflow.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #69 | Add tests for `wp-new -> session handoff` success and failure modes | `enhancement` |
| #61 | Document target model: main session vs side sessions | `documentation` |
| — | Document fallback behavior outside OpenCode context | `documentation` |

**Expected Artifacts:**

- automated tests covering create/switch/ambiguity/API-failure paths
- user-facing docs for integrated flow
- maintainer-facing docs for target model policy

**Verification:**

- tests cover integrated behavior rather than only standalone `/wp`
- docs explain when handoff occurs and when it does not

---

## Blockers & Risks

| Blocker/Risk | Impact | Mitigation |
|-------------|--------|------------|
| `wp-new` may run in contexts where OpenCode TUI is not available | Automatic handoff may fail unexpectedly | Make handoff best-effort and never block successful work-product creation |
| Target model rules are underspecified | Main and side sessions may drift into ambiguity | Keep ADR-011 as the source for main/side/reopen policy and test it explicitly |
| Over-automation creates too many sessions | Session history becomes noisy | Apply the model primarily to full execution work products, not all micro-items |

---

## Ready Gate Checklist

Before marking this plan as `Ready for execution`:

- [x] ADR status: `Accepted`
- [x] All milestones have defined issues
- [x] Dependency order is correct
- [x] No blocking unknowns
- [x] archgate passed
- [x] Security reviewed: wrong-session switching remains ambiguity-safe
- [x] Verification strategy defined per milestone

---

## Exit Criteria

- [ ] `wp-new` can trigger automatic session handoff after successful creation
- [ ] Main-session preference is preserved during automatic handoff
- [ ] Side sessions are never silently treated as canonical main sessions
- [ ] Handoff failures do not undo work-product creation
- [ ] Tests cover integrated workflow paths
- [ ] ADR-011 status updated appropriately

---

## Summary

| Milestone | Status | Issues |
|-----------|--------|--------|
| M0: Design alignment | Ready | #66, #68 |
| M1: Workflow integration | Ready | #62, #63 |
| M2: Session policy enforcement | Ready | #67, #65, #64 |
| M3: Verification and documentation | Ready | #69, #61 |
