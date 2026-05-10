# ADR-013: Model Tier Abstraction — Provider-Agnostic Model Selection

**Status:** Proposed
**Date:** 2026-05-10
**Context:** FMT-exocortex-template, `persistent-memory/`, `.claude/skills/`, `scripts/ai-cli-wrapper.sh`

---

## Context

ADR-008 abstracted the **CLI layer** — replacing `claude` binary, `CLAUDE_PATH`, `ANTHROPIC_API_KEY` with provider-agnostic equivalents. Users can now run `AI_CLI=opencode` and the wrapper translates flags correctly.

However, **model selection** remains hardcoded to Anthropic model names at the operational rule level:

```
persistent-memory/protocol-open.md:69:
| trivial | Не нужна | Автономно | Haiku       |  ← Haiku не существует у DeepSeek
| closed-loop | Тесты | Автономно | Sonnet   |  ← Sonnet не существует у OpenAI
| open-loop | Дорогая | Совместно | Opus      |  ← Opus не существует у DeepSeek
```

Total: **72 conceptual references** to Haiku/Sonnet/Opus across 10 operational files. When `AI_CLI=opencode` with DeepSeek or GPT, the system continues to recommend "Haiku" for verification — a model that doesn't exist at those providers. Users must manually guess the equivalent.

## Problem

1. **Vendor lock-in at model level:** Protocols, skills, and rules reference Anthropic model family names (Haiku/Sonnet/Opus) as capability tiers. These names are meaningless for non-Anthropic providers.
2. **Sub-agent delegation is broken:** The rule «Opus→Sonnet→Haiku, только вниз» assumes an Anthropic-specific capability hierarchy. DeepSeek and OpenAI have different hierarchies.
3. **Verification class VT.001/VT.002/VT.003** (TESTING.md:664-666) is tied to model names rather than objective capability characteristics.
4. **72 places to update** when switching providers — the exact same class of problem ADR-008 solved for CLI names.

## Decision Drivers

1. **Complete ADR-008:** CLI abstraction without model abstraction is half-finished. Provider switch must work end-to-end.
2. **Backward compatibility:** Existing users with `claude` + Anthropic models must see zero behavioral change.
3. **Provider-agnostic rules:** Protocols should reason about capability tiers, not specific model names.
4. **Extensible by users:** Users with access to custom models or new providers should be able to add mappings without forking the template.
5. **Single source of truth:** One file maps tiers to models per provider. All operational files reference tiers.

## Decision

### Chosen approach: Capability tiers + mapping file

Introduce 3 provider-agnostic **capability tiers** that replace Anthropic model names everywhere:

| Tier | Replaces | Characteristics |
|------|----------|----------------|
| `fast` | Haiku | Low cost, basic reliability, context isolation, suitable for R23 verification |
| `thinking` | Sonnet | Medium cost, high reliability, autonomous execution, suitable for closed-loop tasks |
| `pro` | Opus | Maximum cost, expert quality, collaborative mode, captures required |

### Mapping file: `seed/model-tiers.yaml`

```yaml
# Model tier mapping per provider
# Format: provider → {fast, thinking, pro} → model_id
# Users can override per workspace to match their API access.

anthropic:
  fast:     claude-haiku-4-5-20251001
  thinking: claude-sonnet-4-20250514
  pro:      claude-opus-4-20250514

deepseek:
  fast:     deepseek/deepseek-chat
  thinking: deepseek/deepseek-reasoner
  pro:      deepseek/deepseek-reasoner

openai:
  fast:     openai/gpt-4o-mini
  thinking: openai/gpt-4o
  pro:      openai/o1
```

### Resolution strategy: project-level default + workspace override

```
ai-cli-wrapper.sh: resolve_model(tier)
  ├── $WORKSPACE/model-tiers.yaml  (user override, NOT overwritten by update.sh)
  └── seed/model-tiers.yaml        (template default, versioned)
```

Same pattern as `seed/params.yaml`: the template provides sensible defaults for all supported providers. A workspace can override individual model IDs if the user has different API access or wants to use a custom provider.

### Architecture Diagram

```
┌──────────────────────────────────────────────────┐
│  protocol-open.md / verify SKILL / day-close ... │
│  "запустить sub-agent fast-тира (R23)"            │
└────────────────────┬─────────────────────────────┘
                     │ tier name ("fast")
                     ▼
┌──────────────────────────────────────────────────┐
│              ai-cli-wrapper.sh                    │
│  resolve_model("fast")                            │
│    → detect provider (claude|opencode)            │
│    → read model-tiers.yaml[provider][fast]        │
│    → return model ID                              │
│    → opencode: --model <id>                       │
│    → claude:   /model already set, no flag needed │
└──────────────────────────────────────────────────┘
```

### Example conversions

```
Было:  «запустить sub-agent Haiku в роли R23»
Стало: «запустить sub-agent fast-тира в роли R23»

Было:  | open-loop | Дорогая, отложенная | Совместно, Captures | Opus |
Стало: | open-loop | Дорогая, отложенная | Совместно, Captures | pro |

Было:  VT.001 | Trivial | Haiku R23 — autonomous
Стало:  VT.001 | Trivial | fast-тир (R23) — autonomous

Было:  Делегирование только вниз (Opus→Sonnet/Haiku, Sonnet→Haiku)
Стало: Делегирование только вниз (pro→thinking/fast, thinking→fast)
```

## Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| Keep Haiku/Sonnet/Opus, add per-provider aliases | Confusing — two naming systems coexist. Rules still read as Anthropic-first |
| Map all providers to the *same* model names | Breaks reality — DeepSeek has no Haiku. Users must learn a fake namespace |
| Remove tier concept, use raw model IDs everywhere | Loses semantic meaning — rules become unreadable. "Use claude-haiku-4-5-20251001 for verification" is opaque |
| Use numeric tiers (T1/T2/T3) | Less self-documenting than fast/thinking/pro |

## Consequences

### Positive

- Provider switch works end-to-end — CLI + model selection both abstracted
- Rules are provider-agnostic and self-documenting (`fast-тир` is clearer than `Haiku` for non-Anthropic users)
- New providers added by editing one YAML file
- Zero changes to Anthropic user behavior — the tier names are documentation semantics, Anthropic model IDs in the mapping file are identical to current hardcoded values
- Sub-agent delegation rules work across providers

### Negative

- 4-character tier names (`fast`, `pro`) vs 5-6 character model names (`Haiku`, `Sonnet`) — minor visual change, no functional impact
- `deepseek-reasoner` used for both `thinking` and `pro` tiers — DeepSeek has only 2 models, so `thinking` and `pro` map to the same model ID. This is acceptable: the tier is a *capability aspiration*, not a guarantee of distinct models
- `opencode` requires `--model` flag for tier selection, `claude` uses `/model` interactively — handled by wrapper's existing provider-specific flag mapping

### Requires Attention

- `resolve_model()` must handle the case where a tier maps to the same model ID as another tier (DeepSeek: thinking=pro=reasoner). The function should not warn or error — this is a valid provider characteristic.
- R23 role number stays — it's a role identifier, not a model name
- `JUDGE_MODEL` in `seed/agents/tester/deepeval/eval_runner.py` is a separately hardcoded model string — not in scope for this ADR (test infrastructure concern)
- `seed/agents/tester/promptfoo/promptfoo.yaml` — same, test config, separate concern
- `setup/optional/generate-post-image.py:53` — `gpt-image-1.5` is an image-generation model, not an LLM, not in scope

## Migration / Compatibility

**Phase A: Mapping file + wrapper function (this ADR)**
1. Create `seed/model-tiers.yaml` with 3 providers × 3 tiers
2. Add `resolve_model(tier)` to `scripts/ai-cli-wrapper.sh`
3. No existing behavior changes — wrapper function is additive

**Phase B: Replace Haiku/Sonnet/Opus in operational files (implementation plan)**
1. `persistent-memory/protocol-open.md` — table: Haiku→fast, Sonnet→thinking, Opus→pro
2. `persistent-memory/protocol-close.md` — "Haiku R23" → "fast-тир (R23)"
3. `persistent-memory/hard-distinctions.md` — "Haiku/Sonnet" → "fast/thinking"
4. `CLAUDE.md` — "Haiku R23" → "fast-тир (R23)"
5. `.claude/skills/verify/SKILL.md` — 5 strings: Sonnet→thinking, Opus→pro
6. `.claude/skills/day-close/SKILL.md` — "Haiku R23" → "fast-тир"
7. `.claude/skills/week-close/SKILL.md` — same
8. `.claude/skills/run-protocol/SKILL.md` — "Haiku R23" → "fast-тир"
9. `docs/TESTING.md` — VT.001-003 table
10. `docs/LEARNING-PATH.md`, `docs/SETUP-GUIDE.md`, `docs/workflow-full.md` — conceptual references

**Rollback:** Set `AI_CLI=claude` + `AI_CLI_MODEL` env var. Tier names are documentation-only; Anthropic model IDs in `model-tiers.yaml` are identical to current hardcoded values. No behavioral change for Claude users.

## Security Impact

- No new secrets, tokens, or PII
- `model-tiers.yaml` contains only model IDs — no API keys
- `resolve_model()` reads local files, makes no network calls
- Workspace override file (`$WORKSPACE/model-tiers.yaml`) is not version-controlled (gitignored), preventing accidental credential leakage

## Verification Strategy

| Level | Test | How |
|-------|------|-----|
| Unit | `model-tiers.yaml` valid YAML | `yamllint seed/model-tiers.yaml` |
| Unit | `resolve_model` returns correct ID | `bash scripts/ai-cli-wrapper.sh resolve fast` → `claude-haiku-4-5-20251001` |
| Unit | Workspace override respected | Mock `$WORKSPACE/model-tiers.yaml` with different ID |
| Unit | Unknown tier → error | `resolve_model "nonexistent"` → exit 1 + message |
| Smoke | `bash -n` on modified scripts | All modified `.sh` files pass syntax check |
| E2E | Day Close with `AI_CLI=opencode` | Verifier sub-agent uses `fast` tier → DeepSeek Chat |

## Related

| Document | Relationship |
|----------|-------------|
| `docs/adr/ADR-008-ai-provider-abstraction.md` | CLI-level abstraction — this ADR completes the model-level piece |
| `docs/adr/ADR-002-modular-roles.md` | Roles (verifier, strategist) use model tiers for sub-agent selection |
| `docs/adr/ADR-009-testing-strategy.md` | Test infrastructure uses LLM-as-Judge with model selection |

## Tracking

- Project: [FMT-exocortex-template](https://github.com/abcdef0101/FMT-exocortex-template/projects)
