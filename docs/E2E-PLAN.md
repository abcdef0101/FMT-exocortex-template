# E2E Test Plan — Full IWE Workflow Coverage

> Created: 2026-05-08
> Based on: `docs/workflow-full.md`, ADR-009
> Goal: E2E coverage for all 15 IWE workflow sections

---

## Current State

| Type | Count | Coverage |
|------|:-----:|----------|
| Structural E2E | 5 | setup, update, migration, sync, conflict |
| AI smoke (eval-only) | 11 | semantic quality checks |
| AI smoke (--run) | 4 | Day/Week/Quick Close, wp-new |
| Assert scripts | 4 | structural invariants after AI |
| Canary tests | 2 | replay + WP Gate emulation |
| **E2E workflow coverage** | | **~20%** |

## E2E Test Definition

E2E-тест = 4-шаговый цикл:

```
seed (workspace + seed data)
  → --run (AI выполняет workflow)
    → assert (структурные инварианты)
      → judge (LLM-оценка качества)
```

## New E2E Tests (10)

| # | Workflow | § | Seed | Run | Assert | Judge | Budget |
|---|----------|---|---|:--:|:----:|:----:|:------:|
| E2E-11 | Day Open | §6 | ✅ | ❌ | NEW | ✅ | $0.50 |
| E2E-12 | Day Close | §9 | ✅ | ✅ | ✅ | ✅ | $1.00 |
| E2E-13 | Week Close | §10 | ✅ | ✅ | ✅ | ✅ | $1.00 |
| E2E-14 | Strategy Session | §5.2 | ✅ | ❌ | ❌ | ✅ | $1.00 |
| E2E-15 | Session Prep | §5.1 | ✅ | ❌ | ❌ | ✅ | $1.00 |
| E2E-16 | Note Review | §8 | ✅ | — | — | ✅ | $0.50 |
| E2E-17 | Quick Close | §7 | ✅ | ✅ | ✅ | ✅ | $0.50 |
| E2E-18 | wp-new | §11 | ✅ | ✅ | NEW | ✅ | $0.50 |
| E2E-19 | WP Gate | §4 | NEW | NEW | NEW | NEW | $0.25 |
| E2E-20 | ORZ Full Cycle | §3 | NEW | NEW | NEW | NEW | $2.00 |

## What's Ready vs What Needs Work

### Ready — just integrate (4 E2Es)

| E2E | Files ready | Action |
|-----|-------------|--------|
| E2E-12 | seed-day-close + eval-day-close + assert-day-close | Wire into runner |
| E2E-13 | seed-week-close + eval-week-close + assert-week-close | Wire into runner |
| E2E-17 | seed-quick-close + eval-quick-close + assert-quick-close | Wire into runner |
| E2E-18 | seed-wp-new + eval-wp-new → need assert | Create assert-wp-new.sh |

### New files needed (6 files)

| E2E | Files | Lines |
|-----|-------|:----:|
| E2E-11 | `assert-day-open.sh` | ~50 |
| E2E-18 | `assert-wp-new.sh` | ~40 |
| E2E-19 | `seed-wp-gate-e2e.sh` + `assert-wp-gate.sh` + `rubrics-wp-gate.yaml` | ~120 |
| E2E-20 | `seed-orz-cycle.sh` + `assert-orz-cycle.sh` + `rubrics-orz-cycle.yaml` | ~150 |

### Runner

| File | Lines | Purpose |
|------|:----:|---------|
| `run-e2e-ai.sh` | ~50 | Executes full E2E cycle for one or all AI workflow tests |

## Implementation Plan

### Phase E1: Already Ready (4 issues)

1. **E2E-18 assert-wp-new.sh** — create assert script for wp-new output
2. **E2E runner** — `run-e2e-ai.sh` orchestrator
3. **Integrate E2E-12/13/17** — wire into runner

### Phase E2: New Tests (3 issues)

4. **E2E-11 assert-day-open.sh** — create assert for Day Open output
5. **E2E-19 WP Gate** — seed + assert + rubrics
6. **E2E-20 ORZ Cycle** — seed + assert + rubrics

## Success Criteria

| Criterion | Target |
|-----------|:------:|
| E2E tests passing threshold | 10/10 |
| Total E2E count | 5 structural → **15** (5 structural + 10 AI) |
| IWE workflow coverage | 20% → **≥80%** |
| CI gate: assert scripts | 8/8 pass |

---

*Created: 2026-05-08*
