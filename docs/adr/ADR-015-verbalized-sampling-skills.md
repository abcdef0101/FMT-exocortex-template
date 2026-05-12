# ADR-015: User-Level Verbalized Sampling Skills

**Status:** Implemented
**Date:** 2026-05-12
**Context:** FMT-exocortex-template, `~/.claude/skills/`, user-level agent customization

---

## Context

The user wants three reusable skills built from the paper *Verbalized Sampling: How to Mitigate Mode Collapse and Unlock LLM Diversity*.

Constraints already present in the workspace:

1. Repo-level `.claude/skills/` in `FMT-exocortex-template` is platform-owned and protected by Extensions Gate.
2. User-owned skills are expected to live in `~/.claude/skills/<name>/SKILL.md`.
3. The target behavior is not a one-off prompt, but a reusable agent surface with stable triggers, scope boundaries, and output contracts.
4. Public implementations already exist, but they differ in shape:
   - `gnurio/nurijanian-skills` packages one umbrella `verbalized-sampling` skill with domain templates.
   - `yurekami/anti-sameness-plugin` packages a broader anti-generic plugin with divergence-oriented commands.

The decision is therefore not whether Verbalized Sampling exists, but how to package it safely and predictably inside this environment.

## Problem

Without a formal decision, implementing these skills ad hoc would create four risks:

1. **Ownership drift:** placing them in repo-level `.claude/skills/` would violate Extensions Gate and make updates unsafe.
2. **Trigger ambiguity:** a single generic skill may under-trigger or over-trigger across ideation, simulation, and synthetic data tasks.
3. **Contract drift:** public examples mix `probability`, `confidence`, and `T-score` language; without a decision, downstream expectations become inconsistent.
4. **Security and misuse risk:** without explicit non-use boundaries, the skills can be applied to deterministic or factual tasks where diversity is harmful.

## Decision Drivers

1. **Generativity** (critical) — the skill set should create a reusable pattern, not a one-off prompt bundle.
2. **Evolvability** (critical) — each domain should be adjustable without destabilizing the others.
3. **Security** (critical) — the skills must not expand automation scope or blur safe/unsafe use cases.
4. **Update safety** — user customizations must remain outside platform-managed files.
5. **Paper fidelity** — the v1 implementation should stay close to the probability-based method in the paper.

## Decision

Implement **three separate user-level skills** in `~/.claude/skills/`:

1. `vs-ideation`
2. `vs-simulation`
3. `vs-synthetic-data`

### Architectural choices

1. **User-space placement**
   - All three skills live in `~/.claude/skills/`.
   - No repo-level platform files are modified for skill installation.

2. **Separate bounded responsibilities**
   - `vs-ideation` handles brainstorming, naming, concept generation, and multi-frame option generation.
   - `vs-simulation` handles persona and dialogue simulation where realistic behavioral variance matters more than tail novelty.
   - `vs-synthetic-data` handles example generation for eval/training/test datasets, including edge cases and hard negatives.

3. **Paper-faithful common contract**
   - Default schema is JSON-first.
   - Core fields are `text` plus `probability`.
   - Each skill may add domain fields such as `frame`, `reaction_type`, `pattern_type`, or `label`, but the probability-centered contract remains stable.

4. **No shared runtime library in v1**
   - v1 keeps each skill self-contained in `SKILL.md`.
   - This intentionally duplicates a small amount of guidance to reduce coupling and simplify installation.

5. **Explicit non-use boundaries**
   - The skills must explicitly refuse deterministic/factual/single-correct-answer uses.
   - `vs-synthetic-data` must distinguish between realistic coverage and adversarial/error generation.

### Operating model

Each skill must define:

1. Trigger conditions
2. Non-trigger conditions
3. Preferred VS variant (`VS-Standard`, `VS-CoT`, `VS-Multi`)
4. Default `k` and probability-threshold behavior
5. Output schema
6. Failure modes and mitigations

## Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| One umbrella `verbalized-sampling` skill for all domains | Simpler to install, but weaker trigger precision and poorer bounded-context behavior for ideation vs simulation vs synthetic-data tasks. |
| Prompt snippets only, no skills | Lowest implementation cost, but no reusable agent trigger surface, no stable non-use rules, and no shared contract. |
| Reuse a public skill unchanged | Fastest path, but public implementations either collapse all domains into one umbrella skill or shift away from the paper's probability-centered interface. |

## Consequences

### Positive

- Keeps user customization in user-owned space.
- Preserves a clear contract per domain.
- Makes future refinement local: one skill can evolve without rewriting all use cases.
- Stays close to the paper's JSON + probability workflow.

### Negative

- Some instruction duplication exists across the three skills.
- Invocation cost is higher than direct prompting because VS itself is more verbose.
- There is no centralized helper script in v1 for formatting or validating distributions.

### Requires Attention

- Keep probability semantics consistent across all three skills.
- Prevent trigger overlap from becoming excessive.
- If more VS domains are added later, a shared reference layer may become worth extracting.

## Migration / Compatibility

This is an additive user-space change.

- No existing platform skill is replaced.
- No migration of repo-level files is required.
- Rollback is trivial: remove the three directories from `~/.claude/skills/`.

## Security Impact

- No new secrets, tokens, or external integrations are introduced.
- The primary security risk is **misapplication**: using diversity-oriented skills for deterministic or sensitive tasks.
- Mitigation is contractual, not infrastructural:
  - strong non-use sections
  - explicit schema constraints
  - domain-specific safety notes in `vs-synthetic-data`

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Content | Trigger precision | Review each skill description for clear when-to-use and when-not-to-use boundaries |
| Content | Contract consistency | Verify all three skills use JSON-first output with `text` + `probability` as the core interface |
| Smoke | Ideation skill | Check that `vs-ideation` includes multi-frame coverage and tail-threshold defaults |
| Smoke | Simulation skill | Check that `vs-simulation` defaults to realistic distribution sampling rather than aggressive tail sampling |
| Smoke | Synthetic-data skill | Check that `vs-synthetic-data` includes schema-first, edge-case, and hard-negative guidance |
| Safety | Misuse boundaries | Confirm all three reject deterministic/factual/single-answer tasks |

## ArchGate Review

Critical characteristics selected by the user:

1. Generativity
2. Evolvability
3. Security

Alternatives explicitly considered by the user:

1. One umbrella skill
2. Prompt snippets only

### EMOGSSB profile

| Characteristic | Status | Rationale |
|----------------|--------|-----------|
| Evolvability | ✅ | Separate skills reduce cross-domain coupling and make later edits local. |
| Scalability | ✅ | Three user-level skill directories are operationally trivial and do not introduce shared runtime state. |
| Learnability | ✅ | Domain-specific triggers are easier to understand than one overloaded skill. |
| Generativity | ✅ | The decision establishes a reusable VS packaging pattern for future domains. |
| Speed | ⚠️ | VS prompts are more verbose and can require multi-turn generation, especially for synthetic data. |
| SOTA | ✅ | The design keeps the paper's probability-based method rather than replacing it with looser creativity heuristics. |
| Security | ✅ | No new side-effectful automation or secret handling is introduced; misuse is constrained by explicit scope boundaries. |

### Veto filter

- Critical characteristics:
  - Generativity -> ✅
  - Evolvability -> ✅
  - Security -> ✅
- Blockers (`❌`): none
- Weak characteristics (`⚠️`): Speed only

Verdict: the decision passes ArchGate.

## Compatibility Review

- Compatible with ADR-004: user-level skills do not alter platform-owned path topology.
- Compatible with ADR-005: the change explicitly respects Extensions Gate and keeps user customization out of update-managed platform files.
- Compatible with ADR-002: the decision introduces no new platform role or role coupling.
- No existing accepted ADR is superseded by this decision.

## Related

| Document | Relationship |
|----------|-------------|
| `docs/adr/ADR-004-memory-topology.md` | Confirms separation between platform-owned and runtime/user-owned paths |
| `docs/adr/ADR-005-update-delivery-architecture.md` | Governs update-safe ownership and Extensions Gate |
| `docs/adr/ADR-002-modular-roles.md` | Confirms no role-surface change is introduced |
| `docs/adr/impl/ADR-015-implementation-plan.md` | Implementation plan |

## Tracking

- Umbrella issue: [#229](https://github.com/abcdef0101/FMT-exocortex-template/issues/229)
- Execution issues: [#230](https://github.com/abcdef0101/FMT-exocortex-template/issues/230), [#231](https://github.com/abcdef0101/FMT-exocortex-template/issues/231), [#232](https://github.com/abcdef0101/FMT-exocortex-template/issues/232)
- Project: [ADR-015 VS skill set](https://github.com/users/abcdef0101/projects/15)

## Implementation Summary

Implemented on 2026-05-12.

Artifacts created:
- `~/.claude/skills/vs-ideation/SKILL.md`
- `~/.claude/skills/vs-simulation/SKILL.md`
- `~/.claude/skills/vs-synthetic-data/SKILL.md`

Verification completed:
- frontmatter and user-invocable metadata present in all three skills
- all three define `Use when` and `Do not use when` sections
- all three use a JSON-first contract with `text` + `probability` as the core interface
- ideation uses frame coverage and tail defaults
- simulation defaults to full-distribution realism
- synthetic data defaults to schema-first multi-batch coverage
