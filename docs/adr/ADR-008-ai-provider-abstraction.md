# ADR-008: AI Provider Abstraction — Multi-Provider CLI Support

**Status:** Accepted
**Date:** 2026-05-06
**Context:** FMT-exocortex-template, roles/, scripts/, CI

---

## Context

IWE currently assumes **Claude Code** as the only AI CLI. This is hardcoded at 4 levels:

| Level | Hardcode | Examples |
|-------|---------|----------|
| **Binary** | `claude` CLI name | `command -v claude`, `claude --bare -p` |
| **Variables** | `CLAUDE_PATH`, `ANTHROPIC_API_KEY` | strategist.sh, scheduler.sh, install.sh, CI workflows |
| **npm package** | `@anthropic-ai/claude-code` | packages-firstboot.sh, Containerfile, setup.sh |
| **Flags** | `--bare`, `--dangerously-skip-permissions`, `--allowedTools` | strategist.sh, verifier.sh, test-phases.sh |

Total: **~60 hardcoded references** across 30+ files. OpenCode is installed in the golden image (`npm install -g opencode-ai`) but cannot be used as a provider because the system assumes Claude everywhere.

## Problem

1. **Vendor lock-in:** Users cannot switch from Claude Code to OpenCode (or any future AI CLI) without forking the template
2. **API key naming:** `ANTHROPIC_API_KEY` is provider-specific but used as the generic "AI CLI key"
3. **Flag incompatibility:** Claude Code flags (`--bare`, `--allowedTools`) have no direct equivalent in OpenCode, making scripted headless execution impossible with other providers
4. **Testing gap:** Phase 5b (headless strategy-session) is gated on `ANTHROPIC_API_KEY` — OpenCode users with their own API key cannot test

## Decision Drivers

1. **Open-by-default:** IWE should not be locked to a single AI provider — users must be able to choose
2. **Backward compatibility:** Existing users with `CLAUDE_PATH`/`ANTHROPIC_API_KEY` must continue working without changes
3. **Zero-cost switch:** Switching providers should require changing 1-2 env vars, not rewriting scripts
4. **Test infrastructure:** Container and VM test pipelines must support both providers

## Decision

### Chosen approach: Provider-agnostic env vars + CLI wrapper

Replace Anthropic-specific names with provider-agnostic equivalents, keeping fallback compatibility:

```
CLAUDE_PATH           → AI_CLI_PATH           (CLAUDE_PATH as fallback)
ANTHROPIC_API_KEY     → AI_CLI_API_KEY        (ANTHROPIC_API_KEY as fallback)
CLAUDE_TIMEOUT        → AI_CLI_TIMEOUT        (CLAUDE_TIMEOUT as fallback)
--claude-path         → --ai-cli-path         (--claude-path still accepted)
claude                → $AI_CLI               (defaults to claude)
@anthropic-ai/claude-code → ${AI_CLI_PACKAGE:-@anthropic-ai/claude-code}
```

A new `scripts/ai-cli-wrapper.sh` maps provider-agnostic flags to provider-specific ones:

```
ai_cli_run "prompt" --bare --allowed-tools "Read,Edit,Bash"
  ├── claude:   claude --bare --dangerously-skip-permissions --allowedTools "Read,Edit,Bash" -p "prompt"
  └── opencode: opencode run "prompt" --pure --dangerously-skip-permissions --agent strategist-test
```

### Architecture Diagram

```
┌────────────────────────────────────────────┐
│              test-phases.sh                 │
│   ai_cli_run "prompt" --bare --allowed-..  │
└──────────────────┬─────────────────────────┘
                   │
┌──────────────────▼─────────────────────────┐
│          ai-cli-wrapper.sh                  │
│   detect_ai_cli() → claude | opencode      │
│   ai_cli_flags()  → mapped CLI flags        │
│   ai_cli_run()    → execute with mapping    │
└──────────────────┬─────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
   ┌─────────┐          ┌──────────┐
   │ claude  │          │ opencode │
   │ --bare  │          │ --pure   │
   │ -p "..."│          │ run ".." │
   └─────────┘          └──────────┘
```

## Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| Remove Claude, OpenCode-only | Breaks all existing users. Claude Code has unique features (`--bare`, `--resume`, hooks) not in OpenCode |
| Keep both, user picks at setup time | Doubles maintenance. Every script would need `if claude ... elif opencode ...` |
| Abstract to generic "AI runner" protocol | Over-engineering. Two providers don't justify a protocol layer yet |
| Do nothing (status quo) | Vendor lock-in. Contradicts open-by-default principle |

## Consequences

### Positive

- Users can switch providers with `export AI_CLI=opencode`
- OpenCode API key works for both Phase 3 (smoke) and Phase 5b (headless E2E)
- New providers can be added by extending `ai-cli-wrapper.sh` alone
- Zero breaking changes — all `CLAUDE_PATH` and `ANTHROPIC_API_KEY` users unaffected

### Negative

- Wrapper adds one indirection — debugging requires checking wrapper logs
- `--allowedTools` has no direct OpenCode equivalent → requires pre-created agent
- OpenCode `--pure` ≠ Claude `--bare` — semantics differ (plugins vs full context)
- Phase 5b with OpenCode requires `opencode agent create` beforehand (extra setup step)

### Requires Attention

- `CLAUDE.md` file name is Claude Code convention — OpenCode uses `AGENTS.md`. Not changed here (structural, needs separate ADR)
- `.claude/` directory similarly is Claude-specific. Not changed here
- OpenCode agent management is not idempotent across CI runs — agent must be pre-created

## Migration / Compatibility

**Phase A (implemented in `c1e8ff9`):** All 4 variables renamed with backward-compatible fallbacks.
- Existing users: no change needed. `CLAUDE_PATH` still works as fallback.
- New users: can set `AI_CLI_PATH` directly.

**Phase B (planned):** Wrapper script for flag mapping. No migration needed — wrapper auto-detects provider.

**Phase C (planned):** OpenCode agent creation. One-time setup: `ai_cli_agent_create strategist-test`.

**Phase D (planned):** Documentation for OpenCode users (`AGENTS.md`, `.opencode/`).

**Rollback:** Set `AI_CLI=claude AI_CLI_API_KEY=$ANTHROPIC_API_KEY` — all old behavior restored.

## Security Impact

- API key management unchanged — keys remain in env vars / GitHub Secrets
- `AI_CLI_API_KEY` is a new env var name, same sensitivity as `ANTHROPIC_API_KEY`
- No new attack surface — wrapper adds no network calls, file writes, or privilege escalation
- `--dangerously-skip-permissions` used identically for both providers

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Phase 5a | Wrapper syntax valid | `bash -n scripts/ai-cli-wrapper.sh` |
| Phase 5a | `ai_cli_agent_create` no-op for claude | Unit test in seeder |
| Phase 5b with claude | Existing E2E unchanged | `AI_CLI=claude bash test-from-container.sh --phase 5` |
| Phase 5b with opencode | New E2E path | `AI_CLI=opencode bash test-from-container.sh --phase 5` |
| CI | Both providers in CI matrix | `AI_CLI=claude` and `AI_CLI=opencode` workflow_dispatch inputs |

## Related

| Document | Relationship |
|----------|-------------|
| `docs/adr/ADR-007-golden-image-testing.md` | Test infrastructure that uses AI CLI |
| `docs/adr/ADR-002-modular-roles.md` | Roles that invoke AI CLI (strategist, verifier) |
| `docs/adr/impl/ADR-008-implementation-plan.md` | Implementation plan |

## Tracking

- Umbrella issue: [#65](https://github.com/abcdef0101/FMT-exocortex-template/issues/65)
- M2 issues: [#53](https://github.com/abcdef0101/FMT-exocortex-template/issues/53), [#54](https://github.com/abcdef0101/FMT-exocortex-template/issues/54), [#55](https://github.com/abcdef0101/FMT-exocortex-template/issues/55), [#56](https://github.com/abcdef0101/FMT-exocortex-template/issues/56)
- M3 issues: [#57](https://github.com/abcdef0101/FMT-exocortex-template/issues/57), [#58](https://github.com/abcdef0101/FMT-exocortex-template/issues/58), [#59](https://github.com/abcdef0101/FMT-exocortex-template/issues/59), [#60](https://github.com/abcdef0101/FMT-exocortex-template/issues/60)
- M4 issues: [#61](https://github.com/abcdef0101/FMT-exocortex-template/issues/61), [#62](https://github.com/abcdef0101/FMT-exocortex-template/issues/62), [#63](https://github.com/abcdef0101/FMT-exocortex-template/issues/63), [#64](https://github.com/abcdef0101/FMT-exocortex-template/issues/64)
- Project: [FMT-exocortex-template](https://github.com/abcdef0101/FMT-exocortex-template/projects)
