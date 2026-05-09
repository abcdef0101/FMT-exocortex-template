# E2E Test Plan — Final Coverage (ArchGate, Gates, Roles, Skills)

> Created: 2026-05-08
> Based on: `docs/workflow-full.md` §4, §12, §13
> Goal: Close remaining 15% gap — 85% → 95%+ IWE workflow coverage

---

## Current State

| Covered | Not covered |
|---------|-------------|
| §3 ОРЗ, §4 WP Gate, §5 Strategy, §6 Day Open, §7 Quick Close, §8 Note Review, §9 Day Close, §10 Week Close, §11 wp-new | §4 ArchGate, §4 IntegrationGate, §12 Roles, §13 Skills |

## New E2E Tests (4)

| # | Workflow | § | Mode | Budget |
|---|----------|---|---|:------:|
| E2E-21 | ArchGate — 7-characteristic evaluation | §4 | --run | $0.50 |
| E2E-22 | IntegrationGate — 4-step order check | §4 | --run | $0.50 |
| E2E-23 | Role Execution — strategist runs scenario | §12 | --run | $0.50 |
| E2E-24 | Skill Invocation — /verify pack-entity | §13 | --run | $0.50 |

## What needs creating

### E2E-21 ArchGate (4 files, ~160 lines)

**seed-archgate-e2e.sh:** Workspace with:
- CLAUDE.md (with ArchGate rules from §4)
- `docs/adr/sample-decision.md` — a solution: "Migrate from QEMU golden images to Docker containers for test isolation"

**eval-archgate-e2e.sh:** `--run` mode:
```
Read CLAUDE.md ArchGate rules → read archgate/SKILL.md → 
evaluate sample-decision.md against 7 characteristics →
output ЭМОГССБ table with ✅⚠️❌
```
`--judge` mode: LLM evaluates correctness.

**assert-archgate.sh:**
- 7 characteristic rows present
- ✅/⚠️/❌ scale (no numeric scores)
- 3 veto rules mentioned
- 3 modernity checks (SOTA.002, SOTA.001, SOTA.011)
- ArchGate ≠ Ranker distinction

**rubrics-archgate.yaml:** 8 metrics (thresholds 0.5-0.8)

### E2E-22 IntegrationGate (4 files, ~160 lines)

**seed-integration-gate-e2e.sh:** Workspace with:
- CLAUDE.md (IntegrationGate section)
- `inbox/new-tool-intent.md`: "I need to create a new MCP server for knowledge indexing"

**eval-integration-gate-e2e.sh:** `--run` mode:
```
Read CLAUDE.md IntegrationGate rules → detect new-tool-intent →
enforce 1→2→3→4 order → output gate decision
```
`--judge` mode: LLM evaluates.

**assert-integration-gate.sh:**
- Step 1: Service Clause created (or asked for)
- Step 2: 3 scenarios listed
- Step 3: Role identified (DP.ROLE reference)
- Step 4: Implementation blocked until (1)-(3) done
- P10 penalty mentioned if jump to implementation
- 4 exceptions listed

**rubrics-integration-gate.yaml:** 8 metrics

### E2E-23 Role Execution (3 files, ~90 lines)

**seed-role-execution-e2e.sh:** Workspace with:
- WeekPlan + MEMORY (active WP)
- `roles/strategist/scripts/strategist.sh` symlink
- CLAUDE.md

**eval-role-execution-e2e.sh:** `--run` mode:
```
Run strategist.sh morning scenario with --workspace-dir →
produces DayPlan in current/
```

**assert-role-execution.sh:** 10 assertions (no LLM judge — deterministic)
- DayPlan created in $DS_DIR/current/
- DayPlan has план на сегодня table
- DayPlan has carry-over section
- DayPlan > 10 lines (substantial)
- No script errors in output

### E2E-24 Skill Invocation (3 files, ~90 lines)

**seed-skill-invocation-e2e.sh:** Workspace with:
- Pack file with 2 violations (copied from verifier-pack-entity seed)
- DP standard reference
- CLAUDE.md

**eval-skill-invocation-e2e.sh:** `--run` mode:
```
Invoke /verify pack-entity on the Pack file →
detect violations → output structured findings
```

**assert-skill-invocation.sh:** 10 assertions
- Violations found (≥1)
- Each violation has severity
- Each violation has description
- Output is valid JSON or structured text
- No false positives on valid fields

---

## Implementation

| Phase | E2E | Files | Lines |
|-------|-----|:-----:|:----:|
| 1 | E2E-21 ArchGate | 4 | ~160 |
| 2 | E2E-22 IntegrationGate | 4 | ~160 |
| 3 | E2E-23 Role Execution | 3 | ~90 |
| 4 | E2E-24 Skill Invocation | 3 | ~90 |
| **Total** | | **14** | **~500** |

## Success Criteria

| Criterion | Target |
|-----------|:------:|
| E2E tests passing | 14/14 |
| IWE workflow coverage | 85% → **95%+** |
| Unit tests | 46/46 (unchanged) |

---

*Created: 2026-05-08*
