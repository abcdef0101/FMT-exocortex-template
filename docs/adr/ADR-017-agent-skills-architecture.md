# ADR-017: Agent + Skills Architecture & Pack Placement

**Status:** Accepted
**Date:** 2026-05-12
**Context:** FMT-exocortex-template, `.opencode/agents/`, `.claude/skills/`, `pack/`, `roles/`

---

## Context

IWE roles were implemented across three incompatible formats:

1. **role.yaml** (`roles/*/role.yaml`) — declarative manifest (id, type, runner, install)
2. **Skills** (`.claude/skills/*/SKILL.md`) — interactive algorithms with steps, variables, conditional logic
3. **Sub-agent templates** (`seed/agents/templates/*.md`) — generated via `create-agents.sh` into `.claude/agents/` and `.opencode/agents/`

Additionally, Pack domain knowledge (DP.ARCH.001, DP.M.005, etc.) was stored inside individual workspaces (`$WORKSPACE_DIR/PACK-digital-platform/`), making it inaccessible to agents running in context isolation or when workspace paths differed.

### Inventory before this ADR

| Format | Files | Roles covered |
|--------|-------|---------------|
| `.opencode/agents/` (generated) | 6 agents (5 verifier-* + role-creator) | R23 only |
| `.claude/agents/` (generated) | 6 agents (same) | R23 only |
| `seed/agents/templates/` | 12 templates (6 × 2 formats) | R23 only |
| `.claude/skills/` | 19 skills | R1, R2, R5, R6, R10, R23 |
| `roles/*/role.yaml` | 5 manifests | R1, R2, R8, R23, R24 |
| Pack in workspace | 0 (cloned at runtime) | — |

## Problem

### P1. Three formats, no formal connection

The mapping between role.yaml ↔ skill ↔ agent was by convention only. No file declared which skill implements which role, or which agent corresponds to which role.yaml. Adding a new role required creating up to 7 artifacts in 4 directories (role.yaml, README.md, SKILL.md, agent.claude.md, agent.opencode.md, install.sh, prompts/).

### P2. Sub-agents could not access Pack knowledge

Sub-agents (verifier-archgate, verifier-code) run in context isolation. They cannot read `$WORKSPACE_DIR/PACK-*/pack/` because:
- The path contains a workspace-specific variable
- Pack may not be cloned in the current workspace
- Sub-agents don't inherit `$WORKSPACE_DIR` from the primary agent

Consequence: instructions like «read DP.ARCH.001 §7» were unfulfillable at runtime.

### P3. Generator pipeline was unnecessary

`seed/agents/templates/` → `create-agents.sh` → `.opencode/agents/` was a generation pipeline for 6 static files. The templates only differed in `{{MODEL}}` placeholder — a single `sed` command. This pipeline added complexity without enabling any runtime behavior.

### P4. role-creator agent was architecturally broken

`role-creator` was a sub-agent (`mode: subagent`) with an 11-step interactive dialog. Sub-agents cannot interact with users — they receive a single prompt and return a single response. The agent referenced SKILL.md for instructions but couldn't load it (context isolation).

## Decision

### D1. Agent definition as primary artifact

Each role = one agent definition in `.opencode/agents/*.md`. Agent frontmatter replaces role.yaml for AI-runtime concerns:

| Field | In role.yaml | In agent definition |
|-------|-------------|-------------------|
| id, name, display_name | `id:`, `name:`, `display_name:` | `description:` |
| mode | — | `mode: primary \| subagent \| all` |
| model tier | — | `model: provider/model-id` |
| tools | — | `permission: { edit: allow/deny, ... }` |
| install, runner | `install:`, `runner:` | Remains in roles/*/ (bash automation) |

### D2. Skills as algorithms, agents as runtime identity

```
Agent (.opencode/agents/*.md)     Skill (.claude/skills/*/SKILL.md)
├── WHO: mode, model, permission  ├── HOW: steps, variables, branches
├── WHEN: description → trigger   ├── WHAT: knowledge, checklists, formats
└── CAN: skill permissions        └── Result: loaded via skill tool on demand
```

Agent loads skill via `skill({ name: "archgate" })` when needed. Multiple agents can share the same skill.

### D3. Two verifier agents instead of five

| Agent | Model | Checks |
|-------|-------|--------|
| `verifier` | sonnet | code, capture, chain, adversarial |
| `verifier-heavy` | opus | archgate, wp |

Rationale: only archgate and wp need opus-level reasoning. Consolidation reduces maintenance from 5 agent definitions to 2, while preserving model tier selection where it matters.

### D4. Pack at worktree level (not workspace level)

```
FMT-exocortex-template/
├── pack/                              ← Pack repository (gitignored)
│   └── digital-platform/
│       ├── 02-domain-entities/DP.ARCH.001-*.md
│       └── 03-methods/DP.M.005-*.md
├── .opencode/agents/
├── .claude/skills/
├── workspaces/
│   └── iwe2/DS-strategy/             ← workspace (no Pack here)
└── roles/
```

Benefits:
- Path `pack/digital-platform/...` is **fixed** — no `$WORKSPACE_DIR` variable
- Accessible to all agents (primary and subagent) via Read tool
- One copy shared across all workspaces
- Skills reference Pack by relative path: `pack/digital-platform/02-domain-entities/DP.ARCH.001-platform-architecture.md`

### D5. role.yaml retained for bash automation only

`roles/*/role.yaml` remains for `setup.sh` autodiscovery (install.auto, runner, display_name). This is the bash/timer layer — separate from the AI layer (agent definitions). No duplication: role.yaml = install concerns, agent definition = runtime concerns.

## Consequences

### Deleted

| Artifact | Reason |
|----------|--------|
| `seed/agents/templates/` (12 files) | Generation pipeline eliminated |
| `scripts/create-agents.sh` | No longer needed |
| `scripts/test/test-create-agents.sh` | Tests removed with generator |
| `.claude/agents/` (6 files) | Unified to `.opencode/agents/` |
| `.opencode/agents/verifier-{code,archgate,capture,chain,adversarial}.md` | Replaced by 2 agents |
| `roles/ROLE-CONTRACT.md` | Agent frontmatter replaces schema |
| `roles/ROLE-FIELD-MAP.md` | Agent frontmatter replaces mapping |
| `roles/README-TEMPLATE.md` | Simplified role creation (skill v2) |

### Created

| Artifact | Purpose |
|----------|---------|
| `.opencode/agents/verifier.md` | R23 sonnet subagent |
| `.opencode/agents/verifier-heavy.md` | R23 opus subagent |
| `.opencode/agents/strategist.md` | R1 primary agent |
| `.opencode/agents/architect.md` | R5 all-mode agent |
| `.opencode/agents/extractor.md` | R2 all-mode agent |
| `.opencode/agents/synchronizer.md` | R8 all-mode agent |
| `.opencode/agents/auditor.md` | R24 subagent |

### Modified

| Artifact | Change |
|----------|--------|
| `.claude/skills/verify/SKILL.md` | Agent() calls → Task tool with 2 agents |
| `.claude/skills/role-create/SKILL.md` | v2: generates agent.md instead of 7 artifacts |
| `persistent-memory/roles.md` | Added Agent and Skills columns |
| `roles/README.md` | Updated «How to add a role» instructions |
| `setup.sh` | Removed ROLE-CONTRACT.md references |
| `checksums.yaml` | Regenerated after file changes |

### Test results

54/54 tests pass after migration.

## ArchGate Assessment

| Characteristic | Before | After | Rationale |
|----------------|--------|-------|-----------|
| Evolvability | 5 | 9 | Adding a role = 1 agent file (+ optional prompts/), not 7 artifacts in 4 dirs |
| Scalability | 6 | 8 | 7 agents vs 6 generated — similar, but no generator pipeline |
| Learnability | 4 | 8 | One format to learn (agent.md), not three |
| Generativity | 5 | 8 | Works in FMT template: any user gets working agents from setup.sh |
| Speed | 10 | 10 | No runtime change |
| Modernity | 6 | 9 | Uses OpenCode native agent features (mode, permission, skill tool) |
| Security | 8 | 9 | `permission: edit: deny` on verifier/auditor — explicit, not tools list |

## Open questions

1. **Pack sync mechanism** — how to detect when `pack/` is stale vs upstream Pack? Manual `git pull`? `update.sh --check`?
2. **Multiple Packs** — if user has several Pack repos, all go into `pack/<name>/`?
3. **Migrating existing verifier agents** in user workspaces — the old `.opencode/agents/verifier-*.md` files need cleanup when user runs `update.sh`
