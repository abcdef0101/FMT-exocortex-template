# Service Clauses

Локальные Service Clauses для изменений и функций, которые проектируются внутри этого репозитория до переноса в Pack.

Когда использовать:
- нужно зафиксировать обещание новой функции до реализации
- нет доступного Pack-репозитория с `08-service-clauses/`
- нужно пройти IntegrationGate в проектном контексте

| ID | Title | Status | Date |
|----|-------|--------|------|
| SC-LOCAL-001 | Work Product Creation With Session Handoff | Draft | 2026-05-09 |

Правило:
- если позже появится канонический Pack-документ `DP.SC.NNN`, этот локальный документ должен стать временным черновиком и сослаться на source-of-truth.

Связанные ADR:
- [ADR-011](../adr/ADR-011-wp-new-session-handoff.md) — как обещание SC-LOCAL-001 превращается в workflow и session-handoff политику.
