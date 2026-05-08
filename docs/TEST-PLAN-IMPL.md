# Test Plan — Implementation Details

> Created: 2026-05-08
> Based on: `docs/TEST-PLAN.md`, `docs/workflow-full.md`
> Each test: approach, source files, assertions, edge cases, dependencies

---

## Phase 2 — Protocols & Gates

### Test Structure Pattern

```bash
#!/usr/bin/env bash
# test-<name>.sh — <what it tests> (<source section>)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

# Read source file
# Assert structural invariants
# Assert key sections present
# Assert key rules/patterns found
# Exit with FAIL count
```

### 2.1 test-fallback-chain.sh (#149)

**Source:** `persistent-memory/repo-type-rules.md` (125 lines), `CLAUDE.md §1`

**Approach:** Static structural analysis — grep for sections, count entries in tables, verify naming consistency.

**Assertions:**
1. `repo-type-rules.md` exists and is readable
2. Contains "3 типа репозиториев" or "Base" or "Pack" or "DS" section
3. Contains "Fallback Chain" or "DS → Pack → Base"
4. Contains "source-of-truth" for Pack/Base
5. Contains "Можно" and "Нельзя" rules for at least one type
6. Contains "Repository-first" rule
7. "Context Pack" format mentioned
8. fallback chain order: DS → Pack → Base (SPF → FPF → ZP) in CLAUDE.md or repo-type-rules

### 2.2 test-protocol-open.sh (#150)

**Source:** `persistent-memory/protocol-open.md` (103 lines)

**Approach:** grep for key section headings and rules. Check branching logic.

**Assertions:**
1. File exists and is ≤150 lines (protocol limit)
2. "WP Gate" or "БЛОКИРУЮЩЕЕ" section
3. "Ритуал согласования" or "Ритуал" section
4. WP Gate has 3 branches: "СОВПАДАЕТ", "REGISTRY", "СТОП"
5. Exception "≤15 мин" mentioned
6. "5-place" or "atomic write" or "5 мест" mentioned
7. "open-sessions.log" or "session log" format
8. Extension point: "load-extensions.sh protocol-open"
9. "verification_class" or "problem-framing" mentioned
10. "Issue Funnel" or "WP-debt" mentioned

### 2.3 test-protocol-work.sh (#151)

**Source:** `persistent-memory/protocol-work.md` (239 lines)

**Approach:** grep for routing table, decision types, gate list.

**Assertions:**
1. File exists
2. "Capture-to-Pack" or "Capture" section
3. Routing table with ≥7 knowledge types
4. "Правило (1-3 строки) → CLAUDE.md" route
5. "Доменное → Pack" route (via KE)
6. "Self-correction" rule
7. "Decision Capture" section
8. "только пользовательские" or "user decisions" for Decision Capture
9. "Pre-action Gates" or "MAP.002" or gates list
10. "Pull-before-Commit" rule

### 2.4 test-protocol-close.sh (#152)

**Source:** `persistent-memory/protocol-close.md` (125 lines)

**Approach:** grep for 4-step structure, verification checklist, exception.

**Assertions:**
1. File exists and is ≤150 lines
2. "Quick Close" section
3. 4 steps: commit+push, WP Context, KE, MEMORY.md
4. "Осталось" or "What's Left" format
5. "→ memory:" mandatory field
6. "Haiku R23" or "Верификация" section
7. 5-item checklist or "All committed and pushed" pattern
8. Exception: "≤15 мин" without changes → skip verification
9. "Day Close" delegated to `/day-close`
10. "Week Close" delegated to `/week-close`

### 2.5 test-wp-gate-logic.sh (#153)

**Source:** `CLAUDE.md §2-3`, `persistent-memory/protocol-open.md § WP Gate`

**Approach:** grep CLAUDE.md for gate rules, protocol-open for branch logic.

**Assertions:**
1. CLAUDE.md contains "WP Gate" or "БЛОКИРУЮЩЕЕ"
2. "ЛЮБОЕ задание → протокол Открытия → ДО начала работы"
3. "check-plan.md" referenced
4. "wp-new" referenced for new tasks
5. "MEMORY.md" as WP status source
6. protocol-open.md contains branching logic ("СОВПАДАЕТ"/"REGISTRY"/"СТОП")
7. "≤15 мин" exception clause
8. "5-place atomic write" for new WP

### 2.6 test-archgate-rubric.sh (#155)

**Source:** `.claude/skills/archgate/SKILL.md` (authoritative v3), `CLAUDE.md §5`

**Approach:** grep archgate SKILL.md for ЭМОГССБ characteristics, veto rules, modernity checks.

**Assertions:**
1. archgate/SKILL.md exists and contains "ЭМОГССБ" or 7 characteristics
2. 7 characteristic names present (Эволюционируемость, Масштабируемость, etc.)
3. Scale: ✅/⚠️/❌ (profile without aggregate score)
4. Veto rule: "❌ в critical" → STOP
5. Veto rule: "≥2 ❌" → STOP
6. 3 modernity checks: SOTA.002, SOTA.001, SOTA.011
7. "ArchGate ≠ Ranker" or "gate, не ranker" distinction
8. ArchGate referenced in CLAUDE.md §5
9. "conjunctive screening" or veto-based (v3) mentioned
10. Did NOT find deprecated v2 aggregate score pattern (advisory)

### 2.7 test-integration-gate.sh (#156)

**Source:** `CLAUDE.md §2 IntegrationGate`, `docs/workflow-full.md §4`

**Approach:** grep both files for 4-step order, exceptions list.

**Assertions:**
1. "IntegrationGate" mentioned in CLAUDE.md
2. Step 1: "обещание" or "Service Clause"
3. Step 2: "сценарии" or "минимум 3"
4. Step 3: "роль" or "DP.ROLE"
5. Step 4: "реализация" after (1)-(3)
6. "прыжок в реализацию = P10" or "DP.FM.010"
7. 4 exceptions listed (fix, bugfix, refactor, experimental)
8. "# see DP.SC.NNN, DP.ROLE.NNN" header format

---

## Phase 3 — AI Smoke Tests

### Test Structure Pattern

Each test = 3 files:
- `seed-<name>.sh` — creates workspace with seed data, outputs path
- `eval-<name>.sh` — LLM-as-Judge evaluation, exit 0 (pass) or 1 (fail)
- `rubrics-<name>.yaml` — scoring criteria

### 3.1 day-close-e2e (#161)

**Seed:** Workspace with DayPlan (today), WeekPlan, commits, MEMORY.md, WP context files

**Eval rubric:** 8 metrics — DayPlan updated, итоги таблица, multiplier calculated, praise section, «Завтра начать с», commit done, MEMORY sync, governance batch

**Threshold:** ≥6/8 pass

### 3.2 week-close-e2e (#162)

**Seed:** Workspace with WeekPlan + 5 DayPlans + MEMORY

**Eval rubric:** 8 metrics — итоги таблица, completion rate, carry-over, контент-план, MEMORY sync, lessons rotation, memory audit, клубный пост

**Threshold:** ≥5/8 pass

### 3.3 note-review-e2e (#163)

**Seed:** fleeting-notes.md with 7 notes of different types

**Eval rubric:** Classify each note → compare with expected category

### 3.4 quick-close-e2e (#164)

**Seed:** Workspace with active session state

**Eval:** 4 steps verified: commit+push, WP context updated, KE routed, MEMORY status

### 3.5 wp-new-e2e (#165)

**Seed:** Workspace without the new WP

**Eval:** Verify 5 locations contain the new WP entry

### 3.6 strategy-session-full (#166)

**Extend existing:** seed-strategy-session.sh + eval-strategy-session.sh

### 3.7 session-prep-headless (#167)

**Seed:** Workspace with last week's data + inbox

**Eval:** Verify draft WeekPlan created, old archived, inbox cleared

---

## Phase 4 — Infrastructure

### 4.1 test-strategist-install.sh (#154)

**Approach:** bash -n, grep for usage text, required args, OS detection branches

**Assertions:**
1. bash -n passes
2. Shebang present
3. "darwin" or "macOS" mentioned (OS detection)
4. "systemctl" or "systemd" mentioned (OS detection)
5. "--workspace-dir" required arg
6. "--ai-cli-path" or "--claude-path" required arg

### 4.2 test-mcp-json-schema.sh (#157)

**Source:** `seed/extensions/mcps/*.json`

**Approach:** python3 json.load, check schema

**Assertions:**
1. Files exist in `seed/extensions/mcps/`
2. Valid JSON (python3 json.load)
3. "mcpServers" key present
4. Each server has "type" field
5. "http" type servers have "url"

### 4.3 test-telegram-notify.sh (#158)

**Source:** `roles/synchronizer/scripts/notify.sh`

**Approach:** bash -n, grep for functions, env requirements

**Assertions:**
1. bash -n passes
2. "send_telegram" function
3. "TELEGRAM_BOT_TOKEN" check
4. Usage message or help
5. "templates/" mentioned (agent templates)

### 4.4 test-ci-schedule.sh (#159)

**Source:** `.github/workflows/cloud-scheduler.yml`

**Approach:** YAML validity, cron syntax

**Assertions:**
1. Valid YAML (python3 yaml.safe_load)
2. "schedule" key with cron syntax (5 fields)
3. "backup-memory" job
4. "health-check" job
5. No hardcoded secrets

### 4.5 test-hard-distinctions.sh (#160)

**Source:** `persistent-memory/hard-distinctions.md`

**Approach:** Count ## headings, check format pattern

**Assertions:**
1. File exists
2. ≥45 distinctions (current: 47)
3. Each has "## N." heading format
4. "❌" and "✅" table pattern present
5. Duplicate #42 noted (advisory)

---

*Created: 2026-05-08*
