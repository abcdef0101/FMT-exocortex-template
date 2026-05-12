# Implementation Plan: ADR-015

> **Status:** Done
> **Last updated:** 2026-05-12
> **ADR:** `docs/adr/ADR-015-verbalized-sampling-skills.md`
> **Project:** https://github.com/users/abcdef0101/projects/15
> **Branch:** `0.25.1`

---

## Initial State

| Artifact | Status |
|----------|--------|
| ADR-015 | Draft not yet tracked |
| User-level VS skills in `~/.claude/skills/` | Not implemented |
| Public reference implementations | Researched |

---

## Dependencies and Order

```
M1 (Ideation contract) ──→ M2 (Simulation specialization) ──→ M3 (Synthetic data + smoke-check)
```

Tracking and ADR readiness must exist before M1 execution begins.

---

## Milestones

### M1: Ideation skill foundation

**Scope:**
Create `vs-ideation` as the first paper-faithful VS skill and establish the common output contract.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #230 | Implement `vs-ideation` skill | enhancement, adr |

**Expected Artifacts:**
- `~/.claude/skills/vs-ideation/SKILL.md`

**Verification:**
- Description clearly targets ideation-only triggers
- JSON-first schema includes `text` + `probability`
- Multi-frame and tail-sampling guidance present

### M2: Simulation skill specialization

**Scope:**
Create `vs-simulation` with persona-first context collection and realism-oriented sampling defaults.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #231 | Implement `vs-simulation` skill | enhancement, adr |

**Expected Artifacts:**
- `~/.claude/skills/vs-simulation/SKILL.md`

**Verification:**
- Trigger language targets persona/dialogue simulation
- Default distribution favors realism over aggressive novelty
- Output schema adds reaction metadata without breaking the common contract

### M3: Synthetic-data skill and validation

**Scope:**
Create `vs-synthetic-data` and perform a smoke review across all three skills.

**Issues:**

| # | Title | Labels |
|---|-------|--------|
| #232 | Implement `vs-synthetic-data` skill and smoke-check the VS skill set | enhancement, adr |

**Expected Artifacts:**
- `~/.claude/skills/vs-synthetic-data/SKILL.md`
- Smoke-check summary in session output

**Verification:**
- Synthetic-data modes cover realistic, edge-case, and hard-negative generation
- All three skills have consistent non-use boundaries and core schema
- Installation paths and ownership remain user-space only

---

## Blockers & Risks

| Blocker/Risk | Impact | Mitigation |
|-------------|--------|------------|
| Trigger overlap between the three skills | Wrong skill activation | Keep descriptions narrow and domain-first |
| Over-abstracting shared logic too early | Higher maintenance complexity | Keep v1 self-contained and duplicate small guidance intentionally |
| Misuse on deterministic tasks | Poor output quality / user confusion | Add explicit non-use rules to every skill |

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

- `vs-ideation` created with ideation-specific trigger surface, frame coverage, and tail-sampling defaults
- `vs-simulation` created with persona/situation cards and full-distribution realism defaults
- `vs-synthetic-data` created with schema-first generation, edge-case coverage, and VS-Multi defaulting
- All skills expose core JSON-first `text` + `probability` interfaces and explicit non-use boundaries

---

## Summary

| Milestone | Status | Issues |
|-----------|--------|--------|
| M1: Ideation skill foundation | Done | #230 |
| M2: Simulation skill specialization | Done | #231 |
| M3: Synthetic-data skill and validation | Done | #232 |
