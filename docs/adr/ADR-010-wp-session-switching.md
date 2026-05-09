# ADR-010: OpenCode Work-Product Session Switching

**Status:** Accepted
**Date:** 2026-05-09
**Context:** FMT-exocortex-template, OpenCode TUI, workspace governance, custom commands/plugins

---

## Context

The template already enforces a Work-Product Gate: a task must be attached to a planned work product (`WP-N`) before implementation work starts. In practice, OpenCode sessions and work products are still disconnected.

Current behavior:

1. The user can choose a work product conceptually (`WP-5`, `WP-1`, etc.).
2. OpenCode can list and switch sessions manually through `/sessions`.
3. The repository can record open work-product sessions in `DS-strategy/inbox/open-sessions.log`.
4. There is no platform-supported command that resolves `WP-N` to an OpenCode session and switches the active TUI session automatically.

OpenCode now exposes a public TUI API for session selection by `sessionID` (`/tui/select-session`) in addition to session listing and creation. This makes deterministic in-client switching possible without restarting the TUI.

## Problem

The current flow creates a gap between governance and execution:

1. Choosing a work product does not reliably resume the correct chat session.
2. Users must manually search `/sessions`, visually match titles, and switch by hand.
3. Session titles drift (`WP-5`, `РП5`, freeform names), making manual recovery slower and error-prone.
4. The platform has no stable contract for "choose WP -> continue its operational session".

Without a formal design, adding this behavior ad hoc would change workflow, plugin surface, and session lifecycle semantics without a controlled contract.

## Decision Drivers

1. **Speed**: selecting a work product should switch to the correct operational session with minimal friction.
2. **Security/Safety**: switching must be deterministic and must not jump to the wrong session when titles are ambiguous.
3. **OpenCode-native behavior**: reuse OpenCode session primitives instead of inventing a parallel session system.
4. **Minimal platform state**: avoid a new persistent mapping format unless native session discovery proves insufficient.
5. **Evolvability**: keep the WP-resolution logic isolated behind a plugin/tool boundary.

## Decision

### Chosen approach: custom command plus plugin-backed WP resolver

Introduce a new OpenCode interaction surface that connects work products to OpenCode sessions:

1. Add a project-level custom command `/wp <WP-id>`.
2. Back the command with a plugin tool that performs deterministic WP resolution and session switching.
3. Use native OpenCode session APIs as the source of truth for session discovery:
   - `session.list`
   - `session.create`
   - `tui.selectSession`
4. Use title-based matching with a strict naming convention for newly created sessions:
   - `WP-N: <work-product title>`
5. Do not introduce a separate `WP -> sessionID` persistent mapping in the MVP.
6. If multiple candidate sessions match the same `WP-N`, stop automatic switching and surface ambiguity to the user.

### Resolution flow

```
User runs /wp WP-5
        |
        v
Custom command template
        |
        v
Plugin tool: wp_session_switch
        |
        +--> Validate WP-N in MEMORY.md / WP-REGISTRY.md
        |
        +--> List native OpenCode sessions
        |
        +--> Rank matches by strict title rules
        |      - exact prefix: WP-5:
        |      - exact prefix: WP-5 <space>
        |      - regex: ^WP-5\b
        |      - fallback legacy titles
        |
        +--> 1 match  -> tui.selectSession(sessionID)
        |
        +--> 0 matches -> session.create(title) -> tui.selectSession(sessionID)
        |
        +--> >1 strong matches -> stop, ask user to disambiguate
```

### Architectural boundaries

- **Governance layer** remains responsible for validating that `WP-N` exists.
- **OpenCode plugin layer** becomes responsible for translating `WP-N` into a concrete session action.
- **OpenCode TUI** remains responsible for actual in-client session switching.

### Naming convention

All newly created work-product sessions must use:

```
WP-N: <title>
```

This becomes the platform convention for automatic WP session recovery.

## Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| Prompt-only custom command without plugin/tool | Non-deterministic. The LLM would need to improvise session lookup and switching, which is too fragile for a workflow primitive. |
| Separate persistent `WP -> sessionID` index file | Adds a new persistent state contract and synchronization burden before proving native session discovery is insufficient. |
| Reuse `open-sessions.log` as the authoritative mapping | The log tracks activity, not canonical identity. It is append-oriented and not a strong session-selection contract. |
| Always create a fresh session for each `/wp` invocation | Breaks continuity and defeats the purpose of resuming a work-product session. |
| Do nothing; rely on manual `/sessions` selection | Keeps the governance-to-execution gap and preserves the current friction/error-prone manual workflow. |

## Consequences

### Positive

- WP selection becomes a first-class operational flow.
- The solution reuses OpenCode's native session model instead of duplicating it.
- The MVP avoids introducing another persistent file format.
- The plugin boundary keeps resolution logic isolated and testable.

### Negative

- Title-based discovery is weaker than explicit ID mapping.
- Legacy sessions with inconsistent titles reduce automatic match quality.
- The solution introduces a permanent plugin/tool and custom command to the template.

### Requires Attention

- Session title ambiguity must fail safely, never guess silently.
- The command must stay scoped to the current workspace/repository context.
- If ambiguity becomes common, a follow-up ADR may be needed for explicit mapping.

## Migration / Compatibility

This is a forward-only additive change.

- Existing sessions remain valid.
- Legacy titles are supported as fallback matches where possible.
- New sessions created by the command use the canonical format `WP-N: <title>`.
- No existing user data or transcripts are migrated in the MVP.

Rollback:

- Remove the command and plugin.
- Users can continue using native `/sessions` manually.

## Security Impact

- No new secrets, tokens, or PII are introduced.
- The primary safety risk is session mis-selection; this is mitigated by strict matching and ambiguity stop conditions.
- The plugin must validate that the requested `WP-N` exists before creating or switching sessions.
- Automatic switching is limited to the current OpenCode workspace context.

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Unit | WP normalization | Inputs `5`, `WP-5`, `wp-5`, `РП5` all normalize to `WP-5` |
| Unit | Match ranking | Exact `WP-5:` beats fuzzy/legacy title matches |
| Integration | Existing WP + one matching session | `/wp WP-5` switches current TUI to that session |
| Integration | Existing WP + no matching session | `/wp WP-5` creates `WP-5: <title>` and switches to it |
| Integration | Existing WP + multiple strong matches | Command stops and surfaces ambiguity |
| Integration | Missing WP | Command refuses to create or switch sessions |
| UX smoke | Manual OpenCode use | `/wp WP-5` completes without restarting the TUI |

## ArchGate Review

Critical characteristics chosen for this decision:

1. Speed
2. Security

Alternatives considered during review:

1. Native-session search only through OpenCode session list
2. Explicit session journal / mapping

### EMOGSSB profile

| Characteristic | Status | Rationale |
|----------------|--------|-----------|
| Evolvability | ✅ | The workflow is isolated behind a command/plugin boundary. A future explicit mapping can replace title ranking without changing the user command. |
| Scalability | ✅ | Session listing and ranking are sufficient for a personal workspace. The design adds no high-cardinality shared service. |
| Learnability | ✅ | User mental model is simple: choose `WP-N`, continue its session. Canonical titles reduce hidden rules. |
| Generativity | ✅ | This establishes a reusable pattern for governance-aware OpenCode workflows, not a one-off patch. |
| Speed | ✅ | Reuses native session APIs and avoids manual `/sessions` selection. No extra persistence layer is required in the MVP. |
| SOTA | ✅ | Follows OpenCode's documented TUI/session APIs instead of reverse-engineering or spawning a new client process. |
| Security | ✅ | Strict ranking plus ambiguity-stop avoids silent wrong-session switching; no new secrets or PII are introduced. |

### Veto filter

- Critical characteristics:
  - Speed -> ✅
  - Security -> ✅
- Blockers (`❌`): none
- Weak characteristics (`⚠️`): none

Verdict: the decision passes ArchGate.

## Compatibility Review

- Compatible with ADR-002: keeps behavior behind a bounded execution surface instead of pushing workflow logic into freeform prompts.
- Compatible with ADR-005: introduces a new platform convention (`WP-N: <title>`) and OpenCode assets that remain template-managed and updateable.
- Compatible with ADR-008: specifically builds on OpenCode as a supported execution environment and uses its public TUI/session API.
- No existing accepted ADR is superseded by this decision.

## Related

| Document | Relationship |
|----------|-------------|
| `docs/adr/ADR-002-modular-roles.md` | Keeps execution behavior behind a bounded role/tool surface |
| `docs/adr/ADR-005-update-delivery-architecture.md` | Introduces a new platform-level command/plugin convention that must remain update-safe |
| `docs/adr/ADR-008-ai-provider-abstraction.md` | Builds specifically on OpenCode as a supported execution surface |
| `docs/adr/impl/ADR-010-implementation-plan.md` | Implementation plan |

## Tracking

- Umbrella issue: [#192](https://github.com/abcdef0101/FMT-exocortex-template/issues/192)
- Execution issues: [#194](https://github.com/abcdef0101/FMT-exocortex-template/issues/194), [#193](https://github.com/abcdef0101/FMT-exocortex-template/issues/193), [#196](https://github.com/abcdef0101/FMT-exocortex-template/issues/196), [#195](https://github.com/abcdef0101/FMT-exocortex-template/issues/195)
- Project: [ADR-010 WP session switching](https://github.com/users/abcdef0101/projects/13)
