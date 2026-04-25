# ADR-004: Memory Topology

**Статус:** Accepted
**Дата:** 2026-04-25
**Контекст:** branch 0.25.1, FMT-exocortex-template, Stage 1 refactoring

---

## Контекст

В текущем состоянии проекта одновременно сосуществуют три topology-модели памяти.

### 1. Authoring topology

Платформенные reference/protocol/navigation файлы физически хранятся в template repo в:

`persistent-memory/`

Это фактический source layer платформы.

### 2. Install topology

`setup.sh` materialize-ит workspace следующим образом:

- создаёт `./workspaces/CURRENT_WORKSPACE/memory/`
- копирует туда `seed/MEMORY.md`
- копирует туда `seed/day-rhythm-config.yaml`
- создаёт symlink:
  - `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory -> ../../../persistent-memory/`

То есть install layer уже различает:

- user operational memory
- platform persistent corpus

### 3. Legacy contract topology

Несмотря на это, часть delivery/validation/documentation слоя продолжает считать, что канонические platform files лежат в `memory/*`.

В результате расходятся:

- source structure
- install behavior
- update contract
- validation contract
- documentation contract

## Evidence

Ниже — конкретные признаки drift.

- `setup.sh` materialize-ит workspace через `memory/persistent-memory`
- `CLAUDE.md` уже использует runtime-paths вида:
  - `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/...`
- `seed/MEMORY.md` уже исходит из workspace-local topology и ссылается на:
  - `persistent-memory/hard-distinctions.md`
  - `persistent-memory/fpf-reference.md`
- `persistent-memory/navigation.md` всё ещё использует legacy ссылки:
  - `memory/protocol-open.md`
  - `memory/protocol-close.md`
  - `memory/templates-dayplan.md`
- `update-manifest.json` всё ещё перечисляет platform files как `memory/*`
- CI validator ожидает root-level `memory/*`
- local validator тоже ожидает root-level `memory/*`

## Проблема

В проекте нет единого ответа на вопросы:

- где находится source-of-truth для platform memory;
- где находится user-owned operational memory;
- какие path rules являются нормативными для docs, skills, hooks, scripts, validators и update tooling;
- какие файлы platform-managed, а какие user-managed.

Пока это не определено явно, любой следующий рефакторинг продолжит плодить рассинхрон.

## Decision Drivers

Критичны:

- **Эволюционируемость**
- **Безопасность обновлений**
- **Современность**

## Определения

- **Authoring topology** — как platform memory хранится в template source
- **Install topology** — как setup/update materialize-ят workspace
- **Runtime topology** — как агент и пользователь видят memory внутри workspace

## Решение

### 1. Platform source-of-truth в template

Единственный source-of-truth для platform memory в template repo:

`persistent-memory/`

### 2. User operational memory в workspace

Пользовательские operational files живут только во workspace:

`./workspaces/CURRENT_WORKSPACE/memory/`

Минимально:

- `./workspaces/CURRENT_WORKSPACE/memory/MEMORY.md`
- `./workspaces/CURRENT_WORKSPACE/memory/day-rhythm-config.yaml`

Эти файлы считаются **user-owned**.

### 3. Runtime platform topology

Platform corpus во workspace доступен по пути:

`./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/`

Это runtime projection platform source.

### 4. Projection mechanism

**Основной projection mechanism — symlink.**

Каноническая install/runtime модель:

- template source:
  - `persistent-memory/*`
- workspace runtime:
  - `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory -> ../../../persistent-memory/`

`symlink` сохраняется как основной механизм по умолчанию, потому что он:

- не дублирует platform corpus;
- сохраняет один физический source-of-truth;
- упрощает update;
- уменьшает риск drift между template source и runtime projection;
- делает layering явным.

Generated copy/materialization не является primary mechanism и может существовать только как вспомогательный fallback для специальных случаев, но не как основной topology contract.

### 5. Ownership boundary

Фиксируется явное разделение:

- `persistent-memory/*` — platform-owned source
- `seed/MEMORY.md`, `seed/day-rhythm-config.yaml` — bootstrap templates
- `./workspaces/CURRENT_WORKSPACE/memory/*` — user-owned runtime files
- `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/*` — runtime projection platform corpus через symlink

## Path Rules

### 1. Template-space rules

Файлы, описывающие сам template repo, должны ссылаться на platform corpus как на:

`persistent-memory/*`

Путь `memory/*` не является каноническим template-source path.

### 2. Root-level agent-facing rules

Root-level platform files, которые описывают runtime-контекст пользователя, должны использовать явные workspace paths:

- `./workspaces/CURRENT_WORKSPACE/memory/MEMORY.md`
- `./workspaces/CURRENT_WORKSPACE/memory/day-rhythm-config.yaml`
- `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/...`

Это правило относится к:

- `CLAUDE.md`
- `.claude/skills/*.md`
- `.claude/hooks/*.sh` там, где они указывают путь пользователю
- runtime-oriented platform docs

### 3. Workspace-local rules

Файлы, которые сами живут внутри `./workspaces/CURRENT_WORKSPACE/memory/`, могут использовать короткие относительные ссылки:

- `persistent-memory/hard-distinctions.md`
- `persistent-memory/protocol-open.md`

Причина: внутри workspace-local memory это стабильный локальный namespace, не смешивающий template-space и runtime-space.

### 4. Script/runtime rules

Скрипты не обязаны literal-хардкодить `./workspaces/CURRENT_WORKSPACE/...`, но обязаны вычислять путь, эквивалентный topology contract.

Пример допустимой модели:

- `WORKSPACE_DIR=./workspaces/CURRENT_WORKSPACE`
- `MEMORY_DIR="$WORKSPACE_DIR/memory"`
- `PERSISTENT_MEMORY_DIR="$MEMORY_DIR/persistent-memory"`

### 5. Anti-rule

Путь `memory/*` запрещён как неявный универсальный alias для platform memory в root-level platform files.

Причина: он смешивает template-space и runtime-space и снова создаёт неоднозначность ownership.

## Delivery Contract

`setup.sh`, `update.sh`, manifest generation, validators и CI обязаны следовать одной и той же topology-модели:

- template хранит platform source в `persistent-memory/*`
- setup materialize-ит:
  - `./workspaces/CURRENT_WORKSPACE/memory/`
  - `./workspaces/CURRENT_WORKSPACE/memory/MEMORY.md`
  - `./workspaces/CURRENT_WORKSPACE/memory/day-rhythm-config.yaml`
  - `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/` как symlink
- update tooling обновляет platform source и сохраняет user-owned files
- validators отдельно проверяют:
  - template structure
  - workspace structure
  - symlink integrity

## Migration Policy

Применяется **compat window**, а не hard cutover.

### Phase 1. Dual-read validation

Validators, CI и update-tooling начинают понимать обе модели:

- legacy `memory/*`
- canonical `persistent-memory/*`

При этом canonical topology уже считается предпочтительной.

### Phase 2. Canonical materialization

`setup.sh` и `update.sh` materialize-ят только каноническую workspace topology:

- `./workspaces/CURRENT_WORKSPACE/memory/`
- `./workspaces/CURRENT_WORKSPACE/memory/MEMORY.md`
- `./workspaces/CURRENT_WORKSPACE/memory/day-rhythm-config.yaml`
- `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory/` как symlink

### Phase 3. Path rewrite

Docs, skills, hooks, scripts и validators переводятся на нормативные path rules:

- template-space -> `persistent-memory/*`
- root-level runtime-facing -> explicit workspace paths
- workspace-local files -> relative `persistent-memory/*`

### Phase 4. Contract cleanup

Удаляются legacy references на `memory/*` как template-source model.

### Phase 5. Legacy removal

После стабилизации compatibility fallback снимается из validators, manifest generation и docs.

## Последствия

### Positive

- Появляется один source-of-truth для platform memory.
- Чётко разделяются platform-owned и user-owned файлы.
- Update становится безопаснее для пользовательской памяти.
- Setup, update, manifest и validators можно строить на одной topology-модели.
- `symlink` минимизирует duplication и снижает риск drift.
- Архитектура становится слоистой: authoring -> install -> runtime.

### Negative

- Потребуется массовая правка ссылок в docs, skills, hooks, scripts, validators и manifest.
- На переходный период придётся поддерживать dual-model compatibility.
- `symlink` требует явной проверки целостности в validators и setup/update.
- Некоторые tooling-сценарии должны учитывать, что `memory/persistent-memory` — не directory copy, а link.

### Risks

- Broken symlink после неаккуратного перемещения template repo
- validators и CI могут продолжать проверять старую модель
- scripts могут случайно работать против legacy `memory/*` assumptions

### Mitigations

- проверка symlink integrity в `setup.sh`
- отдельная проверка symlink integrity в validator/CI
- единые path rules для template-space и runtime-space
- removal legacy references только после compat window

## Non-Goals

Этот ADR не определяет:

- структуру `DS-strategy`;
- содержимое `MEMORY.md`;
- semantics протоколов Open/Work/Close;
- конкретную политику обновления user-owned operational files;
- поддержку non-symlink primary topology.

## Альтернативы

### A. `persistent-memory/` как source, workspace `memory/persistent-memory/` как runtime projection через symlink

**Выбрано**

Причины:

- лучшее разделение ownership;
- соответствует текущей physical layout;
- безопаснее для update;
- не дублирует corpus;
- лучше для эволюции architecture layers.

### B. Вернуть `memory/` как канонический root source в template repo

**Отклонено**

Причины:

- это rollback в legacy-модель;
- ухудшается разделение template/runtime;
- снижается update safety;
- требуется отмена уже начатой структурной миграции.

### C. Flatten: копировать platform files прямо в `./workspaces/CURRENT_WORKSPACE/memory/`

**Отклонено**

Причины:

- platform-owned и user-owned файлы смешиваются;
- ownership boundary размывается;
- update становится опаснее;
- validation и explanation сложнее.

### D. Generated copy/materialization как основной projection mechanism

**Отклонено**

Причины:

- создаёт дублирование corpus;
- повышает риск drift;
- усложняет update contract;
- ухудшает эволюционируемость по сравнению с symlink-моделью.

## Validation Criteria

ADR считается реализованным, когда:

- template validators проверяют `persistent-memory/*`, а не legacy `memory/*`;
- setup, update, manifest и CI используют одну topology-модель;
- root-level agent-facing files используют явные workspace paths;
- workspace-local files используют допустимые локальные относительные ссылки;
- `./workspaces/CURRENT_WORKSPACE/memory/persistent-memory` валидируется как корректный symlink;
- ни один protocol, skill, hook или doc не ссылается на несуществующую topology;
- `./workspaces/CURRENT_WORKSPACE/memory/MEMORY.md` не рассматривается как platform-managed artifact.
