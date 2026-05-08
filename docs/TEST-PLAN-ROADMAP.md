# Test Coverage Roadmap

> Based on: `docs/TEST-PLAN.md`
> Created: 2026-05-08

---

## Overview

| Phase | Test Files | Assertions | Type | Timeline | Milestone |
|-------|:----------:|:----------:|------|----------|-----------|
| 1 — Structural & Config | 9 | ~107 | bash unit | 1 week | `test-coverage-phase-1` |
| 2 — Protocols & Gates | 7 | ~64 | bash unit | 2 weeks | `test-coverage-phase-2` |
| 3 — AI Smoke Tests | 14 | ~69 | LLM-as-Judge | 3-4 weeks | `test-coverage-phase-3` |
| 4 — Infrastructure | 5 | ~31 | bash + YAML | 3-4 weeks | `test-coverage-phase-4` |
| **Total** | **35** | **~271** | | **~4 weeks** | |

## Dependency Graph

```
Phase 1 (9 tests, no deps)
  │
  ├─► Phase 2 (7 tests, depends on memory + role structure from Phase 1)
  │
  ├─► Phase 4 (5 tests, depends on CI config + role scripts from Phase 1)
  │
  └─► Phase 3 (14 tests, depends on AI CLI availability + seed data structure)
```

## Execution Rules

1. Each phase = separate GitHub milestone
2. Each test = separate GitHub issue
3. Issue → branch `test-coverage/<id>-<slug>` → PR → merge
4. After each PR: `bash scripts/test/run-phase0.sh` — must be 0 failed
5. Phase complete when all issues in milestone closed AND full suite passes

## Success Criteria

| Criterion | Current | Target |
|-----------|:------:|:------:|
| Unit tests | 17 | **38** |
| AI smoke tests | 2 | **9** |
| IWE workflow coverage | ~40% | **≥85%** |
| Test pass rate | 100% (17/17) | 100% (38/38) |
| CI gates | ShellCheck + bash -n | Unchanged |

---

*Created: 2026-05-08. Updated: 2026-05-08.*
