# ADR-011: Automatic Session Handoff After Work Product Creation

**Status:** Accepted
**Date:** 2026-05-09
**ArchGate:** Passed (profile: 6✅ 1⚠️ 0❌; critical ✅ Безопасность, ⚠️ Скорость — risk accepted; L2.5 Контролируемость ✅, L2.6 Сохранность знаний ✅)
**Context:** FMT-exocortex-template, `wp-new`, OpenCode TUI, Service Clause SC-LOCAL-001

---

## Context

The repository now supports OpenCode work-product session switching through ADR-010:

1. Users can run `/wp WP-N`.
2. OpenCode resolves the work product against `MEMORY.md` / `WP-REGISTRY.md`.
3. The command selects or creates an execution session named `WP-N: <title>`.

Separately, IWE already supports creation of a new work product through the `wp-new` workflow. That workflow writes planning and governance state atomically into multiple artifacts:

- `MEMORY.md`
- `WP-REGISTRY.md`
- `WeekPlan`
- `Strategy.md` where applicable
- `WP-context` file

Today these flows are still separate:

- `wp-new` creates a work product, but does not create or switch an OpenCode execution session.
- `/wp` manages execution sessions, but assumes the work product already exists.

The newly added local Service Clause `SC-LOCAL-001` defines a stronger user-facing promise: when a user creates a new work product, the system should immediately hand them off into the execution session for that work product.

## Problem

Creating a new work product and starting work on it still requires two separate actions:

1. Create the work product.
2. Manually invoke `/wp WP-N` or manually search `/sessions`.

This creates three problems:

1. **Workflow gap:** the governance action "create work product" does not naturally transition into the execution context.
2. **Handoff friction:** users must remember to trigger session switching after the planning step.
3. **Promise mismatch:** `SC-LOCAL-001` defines an integrated behavior, but the current architecture only provides it as two separate commands.

## Decision Drivers

1. **Continuity:** creating a work product should flow directly into execution.
2. **Safety:** failed or ambiguous session selection must not corrupt work-product creation.
3. **Separation of concerns:** `wp-new` should not duplicate session-resolution logic already established in ADR-010.
4. **OpenCode-native integration:** the handoff should reuse native OpenCode session APIs.
5. **Failure isolation:** governance writes must remain durable even if session handoff fails.
6. **Context isolation:** each execution work product should have a recoverable operational context instead of sharing a mixed chat history.
7. **Low operator burden:** the user should not need to remember a second manual step after creating a work product.

## Decision

### Chosen approach: `wp-new` delegates post-create handoff to the ADR-010 session resolver

Extend the work-product creation workflow so that, after successful creation of `WP-N`, it triggers the same session-resolution mechanism introduced by ADR-010.

The integration contract is:

1. `wp-new` remains the owner of work-product creation.
2. After the work product is written successfully, `wp-new` emits a handoff step with `WP-N` and canonical title.
3. The handoff step calls the existing OpenCode session resolver rather than reimplementing session selection logic.
4. The resolver then:
   - selects an existing strong match, or
   - creates `WP-N: <title>`, or
   - stops safely on ambiguity.

### Recommended target model for IWE

The recommended target model is not "one work product, exactly one possible chat forever". It is:

- each полноценный execution work product has one **canonical main session**
- additional **side sessions** are allowed
- automatic handoff always targets the canonical main session only

#### Main session

The main session is the default operational context of a work product.

Rules:

- exactly one main session per active execution work product
- canonical title format:

```
WP-N: <title>
```

- used for:
  - automatic handoff after `wp-new`
  - `/wp WP-N`
  - default resume / reopen behavior

#### Side sessions

Side sessions are allowed for specialized activity around the same work product, for example:

- audit
- review
- spike / exploration
- migration check

Recommended title format:

```
WP-N [audit]: <title>
WP-N [review]: <title>
WP-N [spike]: <title>
```

Rules:

- side sessions are not selected by automatic handoff if a valid main session exists
- side sessions exist by explicit user intent or explicit workflow, not as an accidental replacement for the main session

#### Switch policy

When the system transitions into a work product session, it should behave in this order:

1. Find the canonical main session for `WP-N`.
2. If exactly one main session exists, switch to it.
3. If no main session exists, create `WP-N: <title>` and switch to it.
4. If multiple candidates claim to be main, stop and surface ambiguity instead of guessing.

#### Reopen policy

Reopened work products should, by default, return to the existing main session.

Create a new main-phase session only when there is an explicit lifecycle reason, for example a new phase of work that should not inherit the previous operational context.

#### Umbrella and episodic work products

Umbrella work products may still keep one canonical main session, while deeper or specialized work is handled in side sessions.

If a side activity becomes a real unit of execution with its own lifecycle, it should become its own work product instead of turning into an uncontrolled second main session.

#### Flexibility rule

This model should primarily apply to full execution work products.

Very small, transitional, or purely planning/admin items may remain outside automatic session creation, so that the workflow does not become more rigid than the value it provides.

### Flow

```
User creates new work product
        |
        v
wp-new writes planning artifacts
        |
        +--> if creation failed: stop, no session handoff
        |
        +--> if creation succeeded: pass WP-N + title to session handoff
                     |
                     v
             ADR-010 session resolver
                     |
                     +--> select existing session
                     +--> create canonical session
                     +--> stop on ambiguity
```

### Boundary rules

- `wp-new` does not rank or search sessions itself.
- Session matching rules remain owned by the ADR-010 mechanism.
- A handoff failure must not roll back the already-created work product.
- User-visible output must distinguish between:
  - work product created + session switched
  - work product created + session created and switched
  - work product created + handoff blocked

## Alternatives

| Alternative | Э | М | О | Г | С(кор) | С(овр) | Б | Вердикт |
|-------------|---|---|---|---|--------|--------|---|---------|
| A: Delegation to ADR-010 (chosen) | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ПАСС |
| B: Keep separate | ✅ | ✅ | ⚠️ | ❌ | ✅ | ❌ | ✅ | НЕТ |
| C: Reimplement search in `wp-new` | ❌ | ⚠️ | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | НЕТ |
| D: Always create new session | ⚠️ | ⚠️ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | НЕТ |
| E: Silent best-effort | ⚠️ | ✅ | ⚠️ | ❌ | ✅ | ❌ | ❌ | НЕТ |

## Consequences

### Positive

- Work-product creation becomes a complete planning-to-execution transition.
- Session logic stays centralized behind one resolver.
- The Service Clause promise becomes implementable without inventing a second session contract.
- Planning and execution now share the same unit of work: `WP-N`.
- The target model becomes explicit instead of implicit: users and agents can distinguish canonical execution context from auxiliary discussions.
- Resume and reopen become easier because each execution work product has a canonical operational session.
- Human-to-agent and agent-to-agent handoff improves: `WP-context` remains the formal artifact, while the OpenCode session preserves the live execution context.
- Context pollution is reduced because execution discussion is less likely to mix with unrelated work products.
- The approach creates a stable base for follow-up automation such as session health checks, archival policies, or explicit main-session designation.

### Negative

- `wp-new` now depends on OpenCode-specific execution behavior.
- The workflow becomes more coupled to the active chat client than before.
- More failure states must be communicated clearly to the user.
- The system may create too many sessions if the rule is applied indiscriminately to short-lived or exploratory work products.
- Legacy session history may create ambiguity because existing titles are not always canonical.
- Not every kind of work over a work product maps cleanly to one conversation: architecture framing, implementation, review, and side investigations may still want separate execution contexts.
- The target model adds more policy surface: main-session rules, side-session rules, reopen rules, and umbrella-work-product rules all need to stay coherent over time.

### Requires Attention

- Need a clean fallback when `wp-new` runs outside an OpenCode context.
- Need a decision on whether session handoff is mandatory or optional in non-interactive flows.
- Need explicit UX text for ambiguity and API-unavailable cases.
- Need a policy distinction between a **main execution session** for a work product and auxiliary review/audit sessions that should not participate in automatic handoff.
- Need a reopen policy: when to reuse the prior canonical session and when to create a fresh phase-specific session.
- Need a policy for umbrella or episodic work products, where one work product may legitimately span multiple operational conversations.
- Need to preserve flexibility for very small or transitional work items so the workflow does not become more rigid than the value it provides.
- Need the target model to stay visible in implementation artifacts so that future contributors do not accidentally collapse main and side sessions back into one undifferentiated pool.

## Migration / Compatibility

This is an additive workflow change.

- Existing work products remain valid.
- Existing `/wp` behavior remains valid as a standalone command.
- Users who do not want automatic handoff should still be able to create a work product without losing the governance write.

Potential compatibility question:

- `wp-new` currently behaves as a pure planning workflow. This ADR would expand its promise into planning + execution handoff.

## Security Impact

- No new PII, secrets, or external auth surfaces are introduced beyond the OpenCode session API already used by ADR-010.
- The main safety concern is accidental switching into the wrong session; this remains mitigated by ADR-010 ambiguity-stop behavior.
- The system must never silently skip governance writes because of a handoff error.

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Integration | `wp-new` success + no session exists | Creates WP and creates/switches to `WP-N: <title>` |
| Integration | `wp-new` success + one strong session exists | Creates WP and switches to the existing execution session |
| Integration | `wp-new` success + ambiguous session set | Creates WP but reports blocked handoff |
| Integration | `wp-new` failure | No session handoff occurs |
| Integration | OpenCode API unavailable | WP creation succeeds, handoff reports failure clearly |

## Related

| Document | Relationship |
|----------|-------------|
| `docs/service-clauses/SC-LOCAL-001-work-product-creation-with-session-handoff.md` | User-facing promise this ADR is intended to fulfill |
| `docs/adr/ADR-010-wp-session-switching.md` | Reused session-resolution mechanism |
| `docs/adr/impl/ADR-011-implementation-plan.md` | Implementation plan |
| `.claude/skills/wp-new/SKILL.md` | Existing work-product creation workflow |

## Tracking

- Umbrella issue: —
- M0 issues: #66, #68
- M1 issues: #62, #63
- M2 issues: #67, #65, #64
- M3 issues: #69, #61
- Project: [ADR-011 WP session handoff #14](https://github.com/users/abcdef0101/projects/14)
