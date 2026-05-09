# SC-LOCAL-001: Work Product Creation With Session Handoff

**Status:** Draft
**Date:** 2026-05-09
**Context:** FMT-exocortex-template, IWE workflow, OpenCode TUI

## Promise

Когда пользователь создаёт новый рабочий продукт, система не только фиксирует его в planning artifacts, но и переводит пользователя в рабочую OpenCode-сессию этого РП.

Если подходящей сессии нет, система создаёт новую именованную сессию вида `WP-N: <title>` и переключает текущий чат в неё.

Если безопасно выбрать сессию нельзя, система не переключает чат молча и сообщает причину.

## Consumer

- Пользователь IWE, который создаёт новый РП и хочет сразу начать работу
- Claude/OpenCode как исполнитель workflow `wp-new -> execution session`

## Trigger

- Пользователь создаёт новый РП через IWE
- РП успешно записан в planning/governance артефакты

## Preconditions

- Новый РП валиден и получил номер `WP-N`
- `MEMORY.md`, `WP-REGISTRY.md`, `WeekPlan` и `WP-context` уже обновлены
- OpenCode session API доступен

## Main Flow

1. Система создаёт новый РП через обычный workflow `wp-new`.
2. После успешной записи в planning artifacts система получает `WP-N` и title.
3. Система ищет существующую OpenCode-сессию для этого РП.
4. Если подходящей сессии нет, создаёт новую `WP-N: <title>`.
5. Система переключает активный OpenCode TUI в выбранную или новую сессию.
6. Пользователь продолжает работу уже внутри рабочей сессии РП.

## Alternative Flows

### A1. Existing exact session exists

- РП создан
- находится одна сильная существующая сессия `WP-N: ...`
- выполняется переключение в неё без создания новой

### A2. No session exists

- РП создан
- совпадений нет
- создаётся новая сессия `WP-N: <title>`
- выполняется переключение в неё

### A3. Ambiguity detected

- РП создан
- найдено несколько одинаково сильных кандидатов
- автоматического переключения нет
- пользователь получает controlled fallback с перечислением кандидатов

## Failure Handling

### F1. Work product creation failed

- если `wp-new` не завершился успешно, session handoff не запускается

### F2. OpenCode API unavailable

- РП остаётся созданным
- пользователь получает сообщение, что planning updated, but session handoff failed

### F3. Unsafe session selection

- при неоднозначности система не угадывает и не создаёт дубли без явной причины

## Result

На успешном пути пользователь получает:
- новый `WP-N` в planning artifacts
- активную рабочую OpenCode-сессию этого РП

## Non-goals

- не решает переименование legacy sessions
- не вводит обязательный persistent mapping `WP -> sessionID`
- не меняет правила создания РП вне OpenCode workflow

## Scenarios

### Scenario 1. New execution work starts immediately

Пользователь формулирует новый РП на 4 часа, система создаёт `WP-12`, затем сразу переводит чат в `WP-12: <title>`, чтобы работа началась без ручного поиска `/sessions`.

### Scenario 2. Strategy session produces a new work product

Во время weekly planning появляется новый РП. После подтверждения и записи в planning artifacts пользователь сразу попадает в execution-сессию нового РП.

### Scenario 3. Ambiguous session history

У пользователя уже есть несколько старых сессий по `WP-5`. После создания или повторной активации РП система не делает небезопасное переключение и просит выбрать осознанно.

## Role

- Primary workflow owner: `wp-new`
- Execution session owner: OpenCode `/wp` / session switch mechanism

## Related

- `docs/adr/ADR-010-wp-session-switching.md`
- `docs/adr/impl/ADR-010-implementation-plan.md`
- `docs/use-cases/USE-CASES.md`
