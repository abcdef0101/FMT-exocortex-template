# ADR-005: Архитектура доставки обновлений шаблона

**Статус:** Proposed
**Дата:** 2026-05-01
**Контекст:** FMT-exocortex-template, Рефакторинг архитектуры доставки

---

## Контекст

FMT-exocortex-template — Base/Formats репозиторий: шаблон IWE, который пользователи форкают и устанавливают через `setup.sh`. Версия 0.25.1. Платформа развивается (CHANGELOG: 0.4.0 → 0.25.1), но механизм доставки обновлений пользователям не формализован.

**Текущая модель доставки:**

```
Авторский IWE ──(ручная работа)──→ FMT-exocortex-template (GitHub)
                                          │
                                   git pull (пользователь сам)
                                          │
                                   обновление «надеемся ничего не сломалось»
```

## Проблема

Четыре критических пробела в механизме обновлений:

### 1. `update.sh` не существует

Весь проект ссылается на `update.sh`:
- `setup.sh` (строка 721): `cd $ROOT_DIR && bash update.sh`
- `ONTOLOGY.md`: «§1-4 обновляется через update.sh»
- `params.yaml`: «update.sh НЕ перезаписывает этот файл»
- `seed/extensions/README.md`: «update.sh не трогает extensions/»
- CHANGELOG v0.18.0–0.21.0: описания изменений в update.sh

Но самого скрипта нет. Это фиктивный контракт — пользователи видят инструкцию, которая не работает.

### 2. Нет версионирования компонентов

CHANGELOG.md — prose-документ. Изменения описаны словами, не машиночитаемо. Нельзя определить:
- какая версия у конкретного skill (day-open/SKILL.md — v2.3.0 или v1.0.0 с патчами?)
- какие компоненты изменились между версиями
- является ли изменение breaking change

Без этого `update.sh` не может ответить на вопрос «что изменилось и что мне делать?».

### 3. Нет миграционного фреймворка

Breaking changes происходят регулярно:
- v0.25.0: protocol-close.md сжат с 454 до 97 строк (Day/Week Close алгоритмы вынесены в SKILL.md)
- v0.24.0: DayPlan требует `<details>` collapsible
- v0.18.0: AUTHOR-ONLY механизм заменён на extensions/

Каждый раз пользователь должен прочитать CHANGELOG и вручную адаптироваться. Нет скриптов, которые выполняют механическую часть миграции.

### 4. Нет checksum-enforcement защиты пользовательских правок

Платформа декларирует: «пользователь не должен редактировать L1 файлы» (Extensions Gate). Но нет машиночитаемого enforcement. Если пользователь отредактировал `.claude/skills/day-open/SKILL.md`, а потом обновление перезаписывает этот файл — его правки теряются молча.

## Decision Drivers

Критичны:
- **Эволюционируемость** — обновления не должны ломать пользовательские кастомизации
- **Безопасность** — checksum enforcement, неперезапись user-space
- **Современность** — машиночитаемые контракты, явные миграции, semver

## Решение

Пять механизмов, работающих вместе:

### 1. Seed Manifest (`seed/manifest.yaml`)

Единый декларативный контракт установки: что копируется, куда, с какой стратегией.

```yaml
version: 1.0.0
artifacts:
  - source: seed/CLAUDE.md
    target: workspace/CLAUDE.md
    strategy: copy-if-newer
  - source: seed/MEMORY.md
    target: workspace/memory/MEMORY.md
    strategy: copy-once        # NEVER overwrite — user data
  - source: seed/params.yaml
    target: workspace/params.yaml
    strategy: copy-once
  - source: seed/settings.local.json
    target: workspace/.claude/settings.local.json
    strategy: copy-and-substitute
    placeholders: [ROOT_DIR]
  - source: seed/.mcp.json
    target: workspace/.mcp.json
    strategy: merge-mcp        # мёржить с extensions/mcps/*.json
```

**Стратегии:**
| Strategy | Поведение |
|----------|-----------|
| `copy-once` | Копировать только если target не существует |
| `copy-if-newer` | Копировать если source новее |
| `copy-and-substitute` | Копировать + подставить {{PLACEHOLDER}} |
| `merge-mcp` | Мёржить с пользовательскими MCP из extensions/mcps/ |

`setup.sh` и `update.sh` читают manifest вместо хардкод-логики копирования.

### 2. Checksum-верификация

Файл `checksums.yaml` — SHA-256 хеши всех платформенных файлов. Контракт: «эти файлы не модифицированы пользователем».

**Алгоритм update.sh:**
```
для каждого платформенного файла:
  если локальный SHA-256 == upstream SHA-256 → перезаписать (файл не модифицирован)
  если локальный SHA-256 != upstream SHA-256 → WARN, показать diff, спросить
  если файл в NEVER-TOUCH → SKIP всегда
```

**NEVER-TOUCH (user-space, не проверять checksum):**
- `workspaces/*/memory/MEMORY.md`
- `workspaces/*/params.yaml`
- `workspaces/*/extensions/`
- `workspaces/*/CLAUDE.md`
- `.claude/settings.local.json`

### 3. 3-way merge CLAUDE.md и ONTOLOGY.md

Файлы со смешанным Platform-space / User-space обновляются через `git merge-file`:

- `CLAUDE.md`: L1 (§1–§7 — платформа), L2 (§8 — staging), L3 (§9 — авторское), §10 (workspace-расширение)
- `ONTOLOGY.md`: §1–§4 (Platform-space), §5–§6 (User-space)

Механизм существует с v0.18.0 (`.claude.md.base`), расширяется на ONTOLOGY.md.

### 4. Миграционный фреймворк

Директория `migrations/` с идемпотентными скриптами для breaking changes.

**Конвенции:**
- Именование: `{version}-{component}-{description}.sh`
- Идемпотентность: можно запустить повторно
- Pre-condition: проверить что миграция нужна
- Backup: `.backup` перед изменением
- Post-condition: валидация после миграции
- Логирование: `.claude/logs/migrations.log`

`update.sh` запускает pending миграции (версия > локальной И ≤ upstream) перед обновлением файлов.

### 5. Extension Points как версионированный контракт

Файл `extension-points.yaml` — машиночитаемый каталог 12 extension points. Каждая точка имеет id, protocol, hook, since-версию, params-toggle.

**Правила обратной совместимости:**
1. Добавить точку → MINOR bump
2. Изменить hook → MAJOR bump + migration
3. Удалить точку → MAJOR bump + migration (авто-перенос расширений)
4. Переименовать → MAJOR bump + migration (авто-переименование файлов)

`update.sh` compat-check: перед обновлением проверяет, что все используемые пользователем extension points живы в новой версии.

### Компонентное версионирование

Каждый платформенный модуль получает `MANIFEST.yaml`:

```yaml
component: skill/day-open
version: 2.3.0
dependencies:
  - persistent-memory/templates-dayplan: ">=1.0.0"
breaking_changes:
  - version: 2.0.0
    description: "TodoWrite enforcement"
    migration: migrations/2.0.0-add-todowrite.sh
api_contract:
  inputs: [day-rhythm-config.yaml, extensions/day-open.before.md]
  outputs: [current/DayPlan.md, MEMORY.md]
```

### Авторский пайплайн (`template-sync.sh`)

Только для `params.yaml → author_mode: true`. Формализует синхронизацию авторского IWE → FMT-шаблон:

1. Placeholder-подстановка: авторские пути/имена → `{{HOME_DIR}}`, `{{WORKSPACE_NAME}}`, `{{GITHUB_USER}}`
2. Валидация перед коммитом (validate-template.sh)
3. Интеграция с CI

### Доставочный пайплайн (end-to-end)

```
Авторский IWE (source-of-truth)
    │
    ├── template-sync.sh ──→ FMT-exocortex-template (GitHub, с {{PLACEHOLDER}})
    │                              │
    │                    CI: validate, shellcheck, semver enforcement
    │                              │
    │                    GitHub Release (tag vX.Y.Z)
    │                              │
    │                    Пользователь: git pull / update.sh
    │                              │
    │                    update.sh:
    │                    ├── fetch upstream
    │                    ├── compat-check extensions
    │                    ├── run pending migrations
    │                    ├── checksum-based apply
    │                    ├── 3-way merge CLAUDE.md / ONTOLOGY.md
    │                    └── post-update validate + notify
```

## Альтернативы

### A. Git submodules для платформенных компонентов

Каждый skill/protocol — отдельный git submodule.

**Отклонено.** Причины:
- Избыточная сложность для набора markdown-файлов
- submodule-ы усложняют setup для пользователей без опыта Git
- Версионирование через submodule refs менее читаемо, чем MANIFEST.yaml
- Пользовательские форки становятся хрупкими (detached HEAD, recursive clone)

### B. NPM/nix/brew пакет

Распространять шаблон как пакет менеджера.

**Отклонено.** Причины:
- Шаблон — markdown + bash, не исполняемый пакет
- Пакетные менеджеры заточены под бинарники/библиотеки, а не под конфигурационные файлы
- `setup.sh` уже решает problem discovery (git, gh, node, claude) — пакетный менеджер дублирует эту функцию
- Git-based delivery проще для пользователей, которые уже владеют git (обязательное требование IWE)

### C. Feature flags для всей новой функциональности

Любое изменение платформы — под feature flag в params.yaml.

**Отклонено.** Причины:
- Взрыв комбинаторного пространства: 28 toggles уже существуют, каждое изменение добавляет ещё
- Тестирование всех комбинаций невозможно
- Пользователь не должен решать «включить ли новую архитектуру DayPlan» — это техническое решение платформы
- Feature flags нужны для extensions (пользовательская кастомизация), а не для платформенных изменений

### D. Полная неизменяемость: пользователь никогда не обновляется

Оставить только setup.sh, без update.sh. Пользователь переустанавливает с нуля.

**Отклонено.** Причины:
- Потеря пользовательских данных при переустановке
- Противоречит всей архитектуре (extensions, params.yaml, user-space)
- CHANGELOG показывает 25+ релизов за 2 месяца — без update механизма пользователи остаются на старой версии

## Последствия

### Positive

- **Безопасность обновлений.** Checksum enforcement гарантирует, что пользовательские правки не теряются молча. NEVER-TOUCH список формализует user-space инвариант.
- **Прозрачность.** Пользователь видит: что изменилось, какие миграции применятся, какие extensions затронуты. Не «надеемся что прочитал CHANGELOG».
- **Машиночитаемость.** Manifest-ы, checksums, extension-points.yaml — все контракты парсятся скриптами. update.sh, CI, /extend skill читают одни и те же файлы.
- **Эволюционируемость.** Миграционный фреймворк делает breaking changes управляемыми. Автор может рефакторить платформу, не боясь сломать пользователей.
- **Авторский workflow.** template-sync.sh формализует синхронизацию IWE → шаблон, исключая ручные ошибки (забыл подставить placeholder).

### Negative

- **Усложнение структуры репозитория.** +15–20 новых файлов (manifest-ы, checksums, миграции).
- **Двойная поддержка на переходный период.** Существующие установки без MANIFEST.yaml должны корректно обновляться.
- **Кривая обучения для автора.** template-sync.sh, manifest-ы, миграции — новые концепции, которые нужно освоить.
- **CI-нагрузка.** Дополнительные проверки увеличивают время CI-пайплайна.

### Risks

- **Ложные срабатывания checksum.** Файл изменён git (line endings, permissions), но контент тот же — SHA-256 расходится.
- **Конфликт 3-way merge.** Пользователь и платформа изменили одну и ту же строку CLAUDE.md.
- **Миграция упала на середине.** Состояние зафиксировано в логе, но восстановление требует ручного вмешательства.
- **Broken symlink.** Перемещение template repo ломает `memory/persistent-memory` symlink.

### Mitigations

- **Checksum false positive:** Нормализация перед хешированием (strip trailing whitespace, unified line endings).
- **3-way merge conflict:** Показать diff, предложить ручное разрешение с инструкцией.
- **Migration failure:** Идемпотентность + backup + лог. Повторный запуск безопасен.
- **Broken symlink:** `setup.sh` и `update.sh` проверяют целостность symlink при каждом запуске.

## Non-Goals

Этот ADR не определяет:

- Конкретную реализацию `update.sh` (отдельные issues в проекте)
- Структуру `DS-strategy` или `DS-agent-workspace`
- Содержимое `MEMORY.md`
- Семантику протоколов Open/Work/Close
- Поддержку non-Git доставки (хостинг-платформа — ADR-003)

## АрхГейт (ЭМОГССБ)

| Характеристика | Балл | Обоснование |
|----------------|------|-------------|
| Эволюционируемость | 10 | Миграционный фреймворк + manifest-driven архитектура. Breaking changes управляемы. Платформа может рефакториться без страха сломать пользователей |
| Масштабируемость | 8 | Git-based доставка масштабируется стандартно. Manifest-ы и checksums — статические файлы, не требуют инфраструктуры |
| Обучаемость | 8 | Пользователь видит preview обновления и управляемые миграции вместо «прочитай CHANGELOG и догадайся». Автор осваивает template-sync.sh за один прогон |
| Генеративность | 9 | Extension points с обратной совместимостью. Пользователи могут создавать и шарить extension-пакеты. Миграции как шаблоны для будущих breaking changes |
| Скорость | 8 | update.sh --check за секунды. Полное обновление — минуты. Миграции идемпотентны, повторный запуск мгновенен |
| Современность | 10 | Semver + checksum enforcement + migration framework = best practices из экосистем (Rails migrations, Kubernetes API versioning, npm semver). Машиночитаемые контракты вместо prose |
| Безопасность | 9 | Checksum enforcement предотвращает молчаливую перезапись. NEVER-TOUCH инвариант для user-space. Миграции с backup. 3-way merge с явным разрешением конфликтов |

**Итог:** 62/70 — PASS (≥8 по всем характеристикам).

## Validation Criteria

ADR считается реализованным, когда:

1. `seed/manifest.yaml` существует и `setup.sh` читает его вместо хардкод-логики
2. `checksums.yaml` существует и содержит SHA-256 для всех платформенных файлов
3. `extension-points.yaml` существует и `update.sh` делает compat-check
4. `MANIFEST.yaml` существует для каждого skill, protocol, hook
5. `update.sh` реализован: check, apply (checksum-based), 3-way merge, compat-check, validate, notify
6. `template-sync.sh` реализован: placeholder-подстановка, валидация, CI
7. `migrations/` содержит фреймворк и скрипты для breaking changes v0.16.0–v0.25.1
8. CI проверяет: граф ссылок, semver enforcement, полноту extension-points.yaml
9. Ни один пользовательский файл (NEVER-TOUCH) не перезаписывается update.sh
10. Проверка целостности symlink при каждом setup/update
