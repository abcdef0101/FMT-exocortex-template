# Implementation Plan: ADR-016

> **Status:** Done
> **Last updated:** 2026-05-12
> **ADR:** `docs/adr/ADR-016-vs-router-skill.md`
> **Project:** https://github.com/users/abcdef0101/projects/16
> **Branch:** `0.25.1`

---

## Initial State

| Artifact | Status |
|----------|--------|
| ADR-016 | Draft not yet tracked |
| `verbalized-sampling-router` | Not implemented |
| Specialized VS skills | Implemented via ADR-015 |

---

## Dependencies and Order

```
M1 (Router contract) ──→ M2 (Smoke-check and finalization)
```

---

## Milestones

### M1: Router contract and implementation

**Scope:**
Create a thin router skill that classifies requests into ideation, simulation, synthetic-data, or not-appropriate-for-VS.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #234 | Implement `verbalized-sampling-router` | enhancement, adr |

**Expected Artifacts:**
- `~/.claude/skills/verbalized-sampling-router/SKILL.md`

**Verification:**
- Generic VS requests route correctly
- Ambiguous requests ask one short clarification question
- Refusal path exists for non-VS tasks

### M2: Smoke-check and finalization

**Scope:**
Verify integration between the router and the specialized skill set.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #235 | Smoke-check VS router integration | enhancement, adr |

**Expected Artifacts:**
- Smoke-check summary

**Verification:**
- Router boundaries do not overwrite specialized-skill intent
- Ideation, simulation, and synthetic-data branches all expose the correct schemas and defaults

---

## Blockers & Risks

| Blocker/Risk | Impact | Mitigation |
|-------------|--------|------------|
| Router overtriggers instead of specialized skills | Lower mode precision | Keep router description generic-entry-only |
| Too much duplicated logic in router | Harder maintenance | Keep domain instructions compact and defer depth to specialized skills |
| Ambiguous prompts silently guessed | Wrong mode selection | Require one clarification question instead of guessing |

---

## Ready Gate Checklist

Before marking this plan as `Ready for execution`:

- [ ] ADR status: `Accepted`
- [ ] All milestones have defined issues
- [ ] Dependency order is correct
- [ ] No blocking unknowns
- [ ] archgate passed
- [ ] Migration reviewed (if applicable)
- [ ] Security reviewed (if applicable)
- [ ] Verification strategy defined per milestone

---

## Exit Criteria

- [ ] All milestones implemented
- [ ] All execution issues closed
- [ ] ADR status: `Implemented`
- [ ] Verification summary recorded

---

## Verification Summary

- `verbalized-sampling-router` created as a thin dispatch skill in `~/.claude/skills/`
- router classifies into ideation, simulation, synthetic-data, or not-for-vs
- router asks one short clarification question on ambiguity
- router points to the three specialized skills and their new `references/templates.md` files

---

## Summary

| Milestone | Status | Issues |
|-----------|--------|--------|
| M1: Router contract and implementation | Done | #234 |
| M2: Smoke-check and finalization | Done | #235 |
