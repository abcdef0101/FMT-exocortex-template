# Test Coverage Plan — IWE Full Functionality

> Created: 2026-05-08
> Source: `docs/workflow-full.md` (15 разделов, полная спецификация IWE)
> Goal: systematic test coverage of all IWE functionality

---

## Current State

| Metriс | Value |
|--------|-------|
| Production scripts with bash -n | 23/23 (100%) |
| Unit tests | 17 (100% pass) |
| E2E tests | 5 (100% pass) |
| AI smoke tests | 2 (strategy-session, day-open) |
| Missing test areas | 18 (see below) |

---

## Phase 1: Структурные и конфигурационные

> **Type:** bash unit tests — no LLM required
> **Priority:** P0 — highest gap, immediate impact
> **Estimate:** ~350 lines across 9 files

| # | Test file | What it tests | Source (§ in workflow-full.md) | Assertions |
|---|-----------|---------------|-------------------------------|:----------:|
| 1.1 | `test-memory-limits.sh` | ≤11 files in memory/, ≤100 lines per reference, ≤150 lines per protocol, ≤100 lines MEMORY.md | §2 Memory: 3 слоя, Лимиты памяти | ~15 |
| 1.2 | `test-memory-metadata.sh` | Every file in memory/ has `valid_from`, stale have `superseded_by` | §2 Temporal metadata | ~10 |
| 1.3 | `test-skill-manifests.sh` | All 20 skills have SKILL.md + MANIFEST.yaml with required fields | §13 Инструменты и скиллы | ~20 |
| 1.4 | `test-roles.sh` | All role scripts: bash -n, agent-card.yaml exists, no broken `source` | §12 Роли, Agent Roles | ~15 |
| 1.5 | `test-params-schema.sh` | params.yaml: author_mode, schedule.*, pomodoro.* keys present | §14 params.yaml | ~8 |
| 1.6 | `test-adr-structure.sh` | All ADRs have: number, date, status, context, decision, consequences | §15 ADR и документация | ~15 |
| 1.7 | `test-wp-context-structure.sh` | WP Context files: «Осталось», «Что пробовали», «Что узнали», «Следующий шаг» | §11 Структура WP Context File | ~10 |
| 1.8 | `test-day-rhythm-schema.sh` | day-rhythm-config.yaml: daily_rp array, slug/title/budget fields | §14 day-rhythm-config.yaml | ~6 |
| 1.9 | `test-navigation-links.sh` | navigation.md: all paths resolve, no broken links | §14 VS Code integration | ~8 |

## Phase 2: Протоколы и Gates (логика)

> **Type:** bash unit tests — no LLM required
> **Priority:** P1 — core IWE protocol logic
> **Estimate:** ~300 lines across 7 files

| # | Test file | What it tests | Source (§) | Assertions |
|---|-----------|---------------|-----------|:----------:|
| 2.1 | `test-fallback-chain.sh` | DS → Pack → Base file resolution: exists, readable, correct priority order | §1 Fallback Chain | ~8 |
| 2.2 | `test-protocol-open.sh` | protocol-open.md: WP Gate section, Ritual section, working context | §3 ОРЗ-фрактал, Сессия | ~8 |
| 2.3 | `test-protocol-work.sh` | protocol-work.md: Capture-to-Pack routing, Self-correction trigger | §3 Протокол Работы | ~8 |
| 2.4 | `test-protocol-close.sh` | protocol-close.md: Quick Close 4 steps (commit, WP context, KE, MEMORY) | §7 Quick Close | ~10 |
| 2.5 | `test-wp-gate-logic.sh` | check-plan.md: in plan / not in plan / urgent / contradicts plan pathing | §4 WP Gate | ~12 |
| 2.6 | `test-archgate-rubric.sh` | ArchGate: 7 ЭМОГССБ characteristics present, 3-item modernity checklist | §4 ArchGate | ~10 |
| 2.7 | `test-integration-gate.sh` | IntegrationGate: 1→2→3→4 order enforced, exceptions listed | §4 IntegrationGate | ~8 |

## Phase 3: AI Smoke Tests

> **Type:** LLM-as-Judge (DeepSeek) — requires AI CLI
> **Priority:** P2 — requires live LLM execution
> **Estimate:** ~600 lines across 7 seeds + 7 evaluators

| # | Test | What it tests | Source (§) | Steps |
|---|------|---------------|-----------|:-----:|
| 3.1 | Day Close E2E | 17 steps: collect data, governance batch, archive, drift scan, health check, multiplier, draft, verify, commit | §9 Day Close | 17 |
| 3.2 | Week Close E2E | 15 steps: rotate lessons, collect week data, metrics, insights, content plan, MEMORY sync, iwe-rules-review, memory audit | §10 Week Close | 15 |
| 3.3 | Note Review E2E | 7 categories: НЭП, Task, Domain Knowledge, Implementation, Draft, Personal Data, Noise | §8 Note Review | ~10 |
| 3.4 | Quick Close E2E | 4 steps + Haiku R23 verification | §7 Quick Close | 4 |
| 3.5 | wp-new E2E | Atomic write to 5 locations: REGISTRY, MEMORY, WeekPlan, DayPlan, WP-context | §11 wp-new | 5 |
| 3.6 | Strategy Session — full 8 steps | Opening, review, inbox, НЭП, strategy alignment, plan formation, irregular blocks, approval + sync | §5.2 Strategy Session | 8 |
| 3.7 | Session Prep (headless) | 10 steps: read last week, inbox, НЭП, strategy alignment, Hub-and-Spoke, session agenda, content plan, archive, draft WeekPlan | §5.1 Session Prep | 10 |

## Phase 4: Инфраструктурные

> **Type:** bash unit + YAML schema — no LLM required
> **Priority:** P2 — CI/VM infrastructure
> **Estimate:** ~150 lines across 5 files

| # | Test file | What it tests | Source (§) | Assertions |
|---|-----------|---------------|-----------|:----------:|
| 4.1 | `test-strategist-install.sh` | roles/strategist/install.sh: bash -n, OS detection, timer paths correct | §14 Установка стратегиста | ~6 |
| 4.2 | `test-mcp-json-schema.sh` | extensions/mcps/*.json: valid JSON, required fields, server name matches filename | §14 MCP-серверы | ~10 |
| 4.3 | `test-telegram-notify.sh` | notify.sh: bash -n, message format, does not crash on missing env vars | §14 Telegram-уведомления | ~5 |
| 4.4 | `test-ci-schedule.sh` | cloud-scheduler.yml: YAML valid, cron syntax correct, backup paths exist | §14 Инфраструктура | ~5 |
| 4.5 | `test-hard-distinctions.sh` | persistent-memory/hard-distinctions.md: ≥50 distinctions, each has ID (HD#), title, description | §15 Hard Distinctions | ~5 |

---

## Summary

| Phase | Priority | Files | Assertions | Type |
|-------|:--------:|:-----:|:----------:|------|
| 1 — Structural & Config | **P0** | 9 | ~107 | bash unit |
| 2 — Protocols & Gates | **P1** | 7 | ~64 | bash unit |
| 3 — AI Smoke Tests | **P2** | 14 | ~69 | LLM-as-Judge |
| 4 — Infrastructure | **P2** | 5 | ~31 | bash + YAML |
| **Total** | | **35** | **~271** | |

### After completion

| Metric | Target |
|--------|:------:|
| Unit tests | 17 → 38 |
| E2E tests | 5 → 5 |
| AI smoke tests | 2 → 9 |
| Production scripts under test | 23/23 (unchanged) |
| IWE workflow coverage | ~40% → ~85% |
