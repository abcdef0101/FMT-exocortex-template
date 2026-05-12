# ADR-016: Verbalized Sampling Router Skill

**Status:** Implemented
**Date:** 2026-05-12
**Context:** FMT-exocortex-template, `~/.claude/skills/`, VS skill topology

---

## Context

ADR-015 introduced three specialized user-level Verbalized Sampling skills:

1. `vs-ideation`
2. `vs-simulation`
3. `vs-synthetic-data`

That design optimized for bounded responsibilities and clean domain-specific contracts. Immediately after delivery, the user requested one more surface: an umbrella skill named `verbalized-sampling-router`.

The router is not meant to replace the three specialized skills. Its purpose is to provide a single entry point for ambiguous or generic requests where the user clearly wants Verbalized Sampling but has not chosen the right domain-specific mode.

## Problem

The current skill set has a trade-off:

1. **Strength:** the three specialized skills have sharp boundaries and good domain defaults.
2. **Weakness:** users must already know which skill to invoke, or the model must pick the right one directly.

Without a routing decision, users face two failure modes:

1. They underuse VS because they do not know which skill to start with.
2. They overuse the wrong specialized skill when the task is ambiguous.

At the same time, a naive umbrella skill would recreate the problem ADR-015 explicitly rejected: one overloaded skill that replaces domain boundaries.

## Decision Drivers

1. **Learnability** (critical) — there should be an obvious entry point for generic VS requests.
2. **Generativity** (critical) — the router should expand the skill ecosystem, not collapse it back into one monolith.
3. **Evolvability** (critical) — specialized skills must remain authoritative and independently editable.
4. **Security** (critical) — the router must not route deterministic or sensitive tasks into diversity-oriented flows.
5. **Speed** — routing should add minimal overhead.

## Decision

Add a **thin umbrella skill** named `verbalized-sampling-router` in `~/.claude/skills/`.

### Architectural boundaries

1. The router is an **entry point**, not the canonical implementation of every VS workflow.
2. The three specialized skills remain the authoritative contracts for:
   - ideation
   - simulation
   - synthetic data
3. The router may duplicate a compact summary of each mode's contract, but must not become the richest source of domain guidance.

### Routing policy

The router must classify requests into one of four outcomes:

1. **Ideation** -> use ideation-oriented schema and defaults
2. **Simulation** -> use simulation-oriented schema and defaults
3. **Synthetic data** -> use synthetic-data schema and defaults
4. **Not appropriate for VS** -> refuse and explain why

### Ambiguity rule

If the task is ambiguous between two modes, the router must ask one short clarification question instead of guessing.

### Router scope rule

The router should trigger on:
- generic mentions of Verbalized Sampling
- requests for "use that diversity method"
- requests where multiple plausible answers are needed but the correct domain mode is unclear

The router should not be the preferred trigger when the task already clearly matches one specialized skill.

## Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| No router, direct use only | Preserves purity, but leaves a learnability gap and weak generic entry point. |
| Prompt index only | Helps humans, but does not provide an actual reusable skill surface for routing. |
| Replace the three skills with one umbrella skill | Recreates the overloaded-skill problem rejected in ADR-015 and weakens domain-specific defaults. |

## Consequences

### Positive

- Gives users a single obvious entry point for generic VS requests.
- Preserves the specialized skills as authoritative bounded contexts.
- Makes the VS skill set easier to discover and adopt.

### Negative

- Adds another trigger surface that can overlap with the specialized skills.
- Requires some duplication of routing logic and compact contracts.
- Slightly increases classification overhead before generation.

### Requires Attention

- Router descriptions must stay narrower than specialized skill descriptions.
- The router must fail to clarification, not to guesswork, on ambiguous tasks.
- If the router starts accumulating too much domain logic, it should be slimmed back down.

## Migration / Compatibility

This is an additive change.

- ADR-015 remains valid.
- The three specialized skills remain installed and supported.
- Rollback is trivial: remove `~/.claude/skills/verbalized-sampling-router/`.

## Security Impact

- No new secrets, tokens, or external integrations are introduced.
- Main risk: routing inappropriate tasks into VS flows.
- Mitigations:
  - explicit refusal path for deterministic/factual/sensitive tasks
  - mandatory clarification on ambiguous cases
  - specialized skills remain the deeper source of domain guidance

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Content | Trigger boundaries | Router description should cover generic VS requests but avoid swallowing clear specialized cases |
| Content | Refusal path | Router must explicitly reject deterministic, factual, or sensitive tasks |
| Smoke | Ideation route | Router maps naming/brainstorm/option-generation requests to ideation mode |
| Smoke | Simulation route | Router maps persona/dialogue/reaction requests to simulation mode |
| Smoke | Synthetic-data route | Router maps eval/example/dataset/edge-case requests to synthetic-data mode |
| Smoke | Ambiguity behavior | Router asks one short clarification question instead of guessing |

## ArchGate Review

Critical characteristics selected by the user:

1. Learnability
2. Generativity
3. Evolvability
4. Security
5. Speed

Alternatives explicitly considered by the user:

1. No router, direct use only
2. Prompt index only
3. Single umbrella skill instead

### EMOGSSB profile

| Characteristic | Status | Rationale |
|----------------|--------|-----------|
| Evolvability | ✅ | The router stays thin while specialized skills remain the deeper contracts. |
| Scalability | ✅ | One extra user-level skill adds no shared state or infrastructure. |
| Learnability | ✅ | A generic entry point lowers adoption friction for users who do not know which specialized skill to choose. |
| Generativity | ✅ | The router broadens the ecosystem without collapsing the bounded contexts back into one overloaded skill. |
| Speed | ⚠️ | Routing adds a classification step and may ask one clarification question on ambiguous prompts. |
| SOTA | ✅ | Thin dispatch over specialized modes is aligned with current agent-skill decomposition patterns. |
| Security | ✅ | The router adds no new side effects and explicitly rejects tasks where VS is inappropriate. |

### Veto filter

- Critical characteristics:
  - Learnability -> ✅
  - Generativity -> ✅
  - Evolvability -> ✅
  - Security -> ✅
  - Speed -> ⚠️
- Blockers (`❌`): none
- Weak characteristics (`⚠️`): Speed only

Verdict: the decision passes ArchGate.

## Compatibility Review

- Compatible with ADR-015: the router is additive and keeps the three specialized skills authoritative.
- Compatible with ADR-005: installation remains in user-owned `~/.claude/skills/`.
- No existing accepted ADR is superseded by this decision.

## Related

| Document | Relationship |
|----------|-------------|
| `docs/adr/ADR-015-verbalized-sampling-skills.md` | Defines the three specialized skills that the router dispatches between |
| `docs/adr/ADR-005-update-delivery-architecture.md` | Governs ownership and update safety |
| `docs/adr/impl/ADR-016-implementation-plan.md` | Implementation plan |

## Tracking

- Umbrella issue: [#233](https://github.com/abcdef0101/FMT-exocortex-template/issues/233)
- Execution issues: [#234](https://github.com/abcdef0101/FMT-exocortex-template/issues/234), [#235](https://github.com/abcdef0101/FMT-exocortex-template/issues/235)
- Project: [ADR-016 VS router](https://github.com/users/abcdef0101/projects/16)

## Implementation Summary

Implemented on 2026-05-12.

Artifact created:
- `~/.claude/skills/verbalized-sampling-router/SKILL.md`

Verification completed:
- router description prefers generic entry-point requests and avoids swallowing clear specialized cases
- explicit `not-for-vs` refusal path is present
- ambiguity resolution uses one short clarification question
- branch contracts point to `vs-ideation`, `vs-simulation`, and `vs-synthetic-data`
