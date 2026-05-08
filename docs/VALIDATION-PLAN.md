# IWE Validation Plan

> Based on: ADR-009-testing-strategy.md
> Created: 2026-05-08
> Three-layer strategy: assert (blocking) → judge (advisory) → canary (replay)

---

## Layer 1: Structural Assert Scripts

> **Type:** bash unit tests — blocking CI gate
> **Priority:** P0 — first-ever CI gate for IWE behavior
> **Assertions:** ~45

| # | File | What it validates | Run after |
|---|------|-------------------|-----------|
| V1.1 | `assert-day-close.sh` | DayPlan структура после Day Close: итоги, таблица РП, multiplier, praise, commit | `eval-day-close.sh --run` |
| V1.2 | `assert-week-close.sh` | WeekPlan структура после Week Close: итоги, completion rate, carry-over, content plan, commit | `eval-week-close.sh --run` |
| V1.3 | `assert-quick-close.sh` | Session Close: WP Context updated, MEMORY synced, commit, no Day Close drift | `eval-quick-close.sh --run` |
| V1.4 | `assert-capture-to-pack.sh` | KE routing: правило→CLAUDE.md, домен→Pack, урок→memory/, контент→draft-list | After any --run with KE |

### V1.1 assert-day-close.sh — Implementation Details

**Input:** Workspace directory (after Day Close `--run`), path to DayPlan

**Assertions (~15):**
1. DayPlan has `## Итоги` or `## Итоги дня` section
2. Итоги section contains table (grep `^|` after `## Итоги`)
3. Table has ≥2 data rows (grep -c `^|`)
4. DayPlan has multiplier mention (grep `multiplier\|Multiplier`)
5. DayPlan has `## Praise` or `## Похвала` section
6. DayPlan has `## Завтра начать с` section
7. MEMORY.md modified (diff from before state or newer mtime)
8. WeekPlan modified (diff or mtime)
9. Git has new commit after Day Close
10. Commit message references "day close" or "Day Close" or "итог"
11. No stale temp files left
12. WP-REGISTRY modified (statuses updated)
13. DayPlan longer after run than before (lines increased)
14. No ERROR strings in run output
15. TodoWrite markers present in run transcript (if captured)

**Edge cases:**
- If DayPlan already has итоги (re-run): detect duplicate sections
- If no git repo: skip commit assertions with note
- If MEMORY.md unchanged (all WPs already done): not a failure

### V1.2 assert-week-close.sh — Implementation Details

**Input:** Workspace (after Week Close `--run`), path to WeekPlan

**Assertions (~12):**
1. WeekPlan has `## Итоги W{N}` section
2. Completion rate present (number followed by `%`)
3. Carry-over section or mention
4. Content plan section with ≥1 publication
5. MEMORY.md has updated WP table
6. Number of WPs in MEMORY changed (old removed, new added)
7. Git commit exists
8. Old DayPlans archived (moved from current/)
9. New WeekPlan created or existing modified
10. Lessons section checked (rotation)
11. Commit message references "week close" or "Week Close"
12. No Day Close artifacts (no "Praise" section in WeekPlan)

### V1.3 assert-quick-close.sh — Implementation Details

**Input:** Workspace (after Quick Close `--run`)

**Assertions (~10):**
1. WP Context file has `## Осталось` section
2. `→ memory:` field present in WP Context
3. MEMORY.md WP status updated (in_progress→done or similar)
4. Git commit exists
5. CLAUDE.md or distinctions.md may be modified (KE routing)
6. No DayPlan modifications (not Day Close)
7. No WeekPlan modifications (not Day Close)
8. Session log (open-sessions.log) has close entry
9. Commit message references "quick close" or "close"
10. No multiplier, praise, or other Day Close artifacts

### V1.4 assert-capture-to-pack.sh — Implementation Details

**Input:** Workspace before and after any process with KE step

**Assertions (~10):**
1. Rules captured → CLAUDE.md or distinctions.md modified
2. Domain knowledge → Pack files modified (or marked for Extract)
3. Lessons → memory/ file created or modified
4. Implementation knowledge → DS docs/ or PROCESSES.md modified
5. Content ideas → draft-list.md or similar modified
6. No knowledge type left un-routed
7. Routing matches Capture-to-Pack table in protocol-work.md
8. Decision log updated if user decisions made
9. Fleeting notes processed (bold removed, strikethrough applied)
10. No captures lost (count before = count after + routed)

---

## Layer 2: LLM-Judge (already implemented)

Not part of this plan. 11 AI smoke tests operational (Phase 3 + R3). See `docs/TEST-PLAN.md` §3 and `docs/ROLE-TEST-PLAN.md` §R3.

---

## Layer 3: Canary Replay Tests

> **Type:** AI CLI + bash assertions — weekly health check
> **Priority:** P1 — detects model/prompt degradation
> **Assertions:** ~23

| # | File | What it validates | Frequency |
|---|------|-------------------|-----------|
| V3.1 | `canary-day-close.sh` | Replay Day Close on workspace copy, compare diff | Weekly |
| V3.2 | `canary-wp-gate.sh` | WP Gate emulation: request outside plan → STOP | Weekly |

### V3.1 canary-day-close.sh — Implementation Details

**Approach:**
```bash
1. Copy workspace to temp (cp -a)
2. Run Day Close on canary via ai_cli_run
3. Diff: what files changed?
4. Assert: expected files changed, unexpected unchanged, no deletions
```

**Assertions (~15):**
1. DayPlan modified (итоги added)
2. MEMORY.md modified
3. WeekPlan modified
4. CLAUDE.md NOT modified (governance, not rules)
5. CHANGELOG.md NOT modified
6. No files deleted (only additions/modifications)
7. Git commit exists on canary
8. Canary commit count ≥1
9. Diff shows only expected paths
10. DayPlan lines increased
11. MEMORY.md has different statuses
12. WP-REGISTRY differs
13. No binary files changed
14. No temp files leaked in /tmp
15. Canary cleanup: workspace removed after test

### V3.2 canary-wp-gate.sh — Implementation Details

**Approach:**
```bash
1. Create workspace with WeekPlan and MEMORY
2. Simulate user request for task NOT in plan
3. Call AI via ai_cli_run
4. Assert: response contains WP Gate trigger (STOP or ask)
5. Assert: AI did NOT execute the task
```

**Assertions (~8):**
1. AI response contains "WP Gate" or "БЛОКИРУЮЩЕЕ" or "нет в плане"
2. AI asks question ("добавить в план?", "создать РП?")
3. Task files NOT modified (AI didn't act before gate)
4. No new files created
5. No git commit made (or commit is only gate-related)
6. Response time ≤30 seconds (gate should be fast)
7. AI offers to run `wp-new` or add to plan
8. Multiple gates: run 3 different out-of-plan requests

---

## Summary

| Layer | Files | Assertions | Type | Cost |
|-------|:-----:|:----------:|------|------|
| L1 — Assert | 4 | ~45 | bash, blocking | 0 |
| L2 — Judge | — | — | already done | ~$0.10 |
| L3 — Canary | 2 | ~23 | bash + AI CLI | ~$0.50/week |
| **Total** | **6** | **~68** | | |

### Implementation Order

```
V1.1 assert-day-close.sh → V1.3 assert-quick-close.sh → V1.2 assert-week-close.sh → V1.4 assert-capture-to-pack.sh
  │
  └─► V3.1 canary-day-close.sh → V3.2 canary-wp-gate.sh
```

### Success Criteria

| Criterion | Target |
|-----------|:------:|
| Assert scripts pass on valid Day Close output | 4/4 |
| Assert scripts fail on invalid output | 4/4 |
| Canary replay produces diff with expected paths | yes |
| WP Gate blocks out-of-plan request | 3/3 attempts |
| CI gate catches regression | verified |

---

*Created: 2026-05-08*
