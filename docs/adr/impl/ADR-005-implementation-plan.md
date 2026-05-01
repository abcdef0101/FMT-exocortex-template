# План реализации ADR-005: Архитектура доставки обновлений шаблона

> **Status:** Ready for execution
> **Last updated:** 2026-05-01
> **ADR:** [../ADR-005-update-delivery-architecture.md](../ADR-005-update-delivery-architecture.md)
> **Project:** https://github.com/users/abcdef0101/projects/8
> **Branch:** 0.25.1

---

## Исходное состояние

| Артефакт | Статус |
|----------|--------|
| ADR-005 | ✅ Написан, закоммичен |
| `setup.sh` | ✅ 723 строки (установка) |
| `setup/validate-template.sh` | ✅ 6 проверок |
| `seed/manifest.yaml` | ❌ Не существует |
| `checksums.yaml` | ❌ Не существует |
| `extension-points.yaml` | ❌ Не существует |
| `MANIFEST.yaml` × 19 | ❌ Не существует ни одного |
| `update.sh` | ❌ Не существует |
| `template-sync.sh` | ❌ Не существует |
| `migrations/` | ❌ Не существует |
| GitHub Project V2 | ✅ 5 milestones, 18 issues |

---

## Порядок и зависимости

```
M1 (Фундамент)  ──────┬──────→ M3 (template-sync.sh)
  #12 seed/manifest.yaml│        #22 core
  #13 checksums.yaml    │        #23 validation
  #14 extension-pts.yaml│        #24 CI
  #15 MANIFEST.yaml ×19 │
                        │
         ┌──────────────┘
         ▼
M2 (update.sh)  ──────→ M4 (Миграции)  ──────→ M5 (CI)
  #16 --check             #25 framework           #28 link-graph
  #17 --apply             #26 retroactive         #29 semver
  #18 3-way merge         #27 integration         #30 extension-pts
  #19 compat-check
  #20 post-validate
  #21 tests
```

**Ключевое:** M1 — блокирующая зависимость. Контракты создаются до кода, который их читает.

---

## M1: Фундамент [4 задачи, est. 12–16h]

### #12: `seed/manifest.yaml` — формальный контракт установки

**Создать:** `seed/manifest.yaml`

```yaml
version: 1.0.0
artifacts:
  - source: seed/CLAUDE.md
    target: workspace/CLAUDE.md
    strategy: copy-if-newer
  - source: seed/MEMORY.md
    target: workspace/memory/MEMORY.md
    strategy: copy-once
  - source: seed/params.yaml
    target: workspace/params.yaml
    strategy: copy-once         # NEVER overwrite
  - source: seed/settings.local.json
    target: workspace/.claude/settings.local.json
    strategy: copy-and-substitute
    placeholders: [ROOT_DIR]
  - source: seed/.mcp.json
    target: workspace/.mcp.json
    strategy: merge-mcp
  - source: seed/day-rhythm-config.yaml
    target: workspace/memory/day-rhythm-config.yaml
    strategy: copy-once
  - source: seed/.gitignore
    target: workspace/.gitignore
    strategy: copy-once
```

**Модифицировать:** `setup.sh` — заменить хардкод-копирование (строки 419–451) на чтение manifest.

### #13: `checksums.yaml` — SHA-256 верификация

**Создать:** `checksums.yaml` + `generate-checksums.sh` (утилита для CI)

**Файлы включаются:**
- `.claude/skills/*/SKILL.md`
- `.claude/hooks/*.sh`
- `persistent-memory/*.md`
- `.claude/rules/*.md`
- `roles/*/*.{sh,yaml,md}`
- `setup.sh`, `setup/*.sh`
- `seed/*.{yaml,md,json}`

**Инвариант NEVER-TOUCH (документировать):**
- `workspaces/*/memory/MEMORY.md`
- `workspaces/*/params.yaml`
- `workspaces/*/extensions/`
- `workspaces/*/CLAUDE.md`
- `.claude/settings.local.json`

### #14: `extension-points.yaml` — каталог 12 extension points

**Создать:** `extension-points.yaml` (в корне репозитория)

Для каждой точки: `id`, `protocol`, `hook`, `since`, `params_toggle`, `breaking_history`.

**Модифицировать:** `seed/extensions/README.md` — ссылка на этот файл.

### #15: MANIFEST.yaml × 19 компонентов

**Приоритет P0 (создать немедленно):**

| Директория | Файл |
|-----------|------|
| `persistent-memory/` | `MANIFEST.yaml` (каталог 6 протоколов) |
| `.claude/skills/day-open/` | `MANIFEST.yaml` |
| `.claude/skills/day-close/` | `MANIFEST.yaml` |
| `.claude/skills/week-close/` | `MANIFEST.yaml` |
| `.claude/hooks/` | `MANIFEST.yaml` (каталог 7 хуков) |

**Приоритет P1 (второй заход):**
- `.claude/skills/run-protocol/`, `wp-new/`, `archgate/`, `verify/`, `fpf/`, `ke/`

**Приоритет P2 (третий заход):**
- Остальные skills: `extend/`, `iwe-update/`, `iwe-workspace/`, `iwe-rules-review/`, `add-workspace-mcps/`, `think/`, `setup-wakatime/`, `session-topic-archiver/`, `wakatime/`
- Роли: `roles/strategist/`, `extractor/`, `synchronizer/`, `verifier/`, `auditor/`

**Схема MANIFEST.yaml:**
```yaml
component: skill/day-open
version: 2.3.0
semver: [2, 3, 0]
dependencies:
  - persistent-memory/templates-dayplan: ">=1.0.0"
breaking_changes:
  - version: 2.0.0
    description: "TodoWrite enforcement"
    migration: migrations/2.0.0-add-todowrite.sh
api_contract:
  inputs: [memory/day-rhythm-config.yaml]
  outputs: [current/DayPlan.md, MEMORY.md]
```

---

## M2: update.sh [6 задач, est. 16–24h]

### Структура `update.sh`

```
update.sh [--check] [--apply] [--dry-run] [--yes] [--force]

Фазы:
1. FETCH     — git fetch upstream
2. PREVIEW   — сравнение MANIFEST.yaml локально vs upstream
3. COMPAT    — проверка extension-points: живы ли пользовательские хуки
4. MIGRATE   — запуск pending migration scripts
5. APPLY     — checksum-based обновление (SHA-256 сравнение)
6. MERGE     — 3-way merge CLAUDE.md / ONTOLOGY.md
7. VALIDATE  — post-update validate-template.sh
8. NOTIFY    — сводка: версия X→Y, изменено N файлов, миграции K
```

### #16: `update.sh --check`

```bash
update_check() {
  git fetch upstream --tags
  # Сравнить локальные MANIFEST.yaml с upstream
  # Вывести таблицу: [Файл | Локальная | Upstream | Тип | Миграция?]
}
```

### #17: `update.sh --apply`

```bash
update_apply() {
  for file in $platform_files; do
    local_sha=$(sha256sum "$file" | cut -d' ' -f1)
    upstream_sha=$(yq ".files.\"$file\"" checksums.yaml)
    if [[ "$local_sha" == "$upstream_sha" ]]; then
      cp "$file" "$file.backup" && git checkout upstream/main -- "$file"
    else
      echo "  ⚠ $file: locally modified — SKIPPED"
    fi
  done
}
```

### #18: 3-way merge

Расширить существующий `.claude.md.base` (v0.18.0) на `ONTOLOGY.md`.

### #19: compat-check

Проверить что все расширения пользователя (`workspace/*/extensions/*.md`) используют живые extension points.

### #20: post-update validate

Запуск `validate-template.sh` + проверка symlink + сводка.

### #21: тесты

Сценарии в `/tmp/test-update/`:
- Чистая установка → обновление
- Установка с extensions → compat-check
- Модифицированный L1 файл → WARN
- Конфликт 3-way merge → ручное разрешение
- Dry-run → ничего не изменено
- Идемпотентность → повторный запуск безопасен

---

## M3: template-sync.sh [3 задачи, est. 8–12h]

Только для `params.yaml → author_mode: true`.

### #22: core — placeholder-подстановка

```
template-sync.sh:
1. Читает seed/manifest.yaml — список файлов
2. Копирует из авторского IWE (source-of-truth)
3. Подставляет placeholders:
   /home/iwe/ → {{HOME_DIR}}/
   .../FMT-exocortex-template/ → {{IWE_DIR}}/
   iwe2 → {{WORKSPACE_NAME}}
4. Генерирует checksums.yaml
5. Обновляет MANIFEST.yaml версии
```

### #23: валидация перед коммитом

Запуск `validate-template.sh` как gate.

### #24: CI

GitHub Actions workflow для push.

---

## M4: Миграции [3 задачи, est. 8–10h]

### #25: framework

```
migrations/
├── README.md       # Конвенции (идемпотентность, backup, логирование)
└── _template.sh    # pre_check → backup → migrate → post_check → log
```

### #26: ретроактивные миграции

| Версия | Что | Файл |
|--------|-----|------|
| 0.25.0 | protocol-close 454→97 строк | `migrations/0.25.0-protocol-close-compress.sh` |
| 0.24.0 | DayPlan collapsible | `migrations/0.24.0-dayplan-collapsible.sh` |
| 0.18.0 | AUTHOR-ONLY → extensions | `migrations/0.18.0-author-only-to-extensions.sh` |

### #27: интеграция с update.sh

Вызов pending миграций перед фазой APPLY.

---

## M5: CI усиление [3 задачи, est. 4–6h]

### #28: проверка графа ссылок

- CLAUDE.md → persistent-memory/* ссылки живы
- navigation.md → только существующие файлы
- role.yaml → обязательные поля

### #29: semver enforcement

Наличие migration script → MAJOR bump обязателен.

### #30: проверка extension-points.yaml на полноту

Все `**EXTENSION POINT:**` маркеры имеют запись в YAML.

---

## Стартовый чек-лист (M1)

- [ ] Создать `seed/manifest.yaml` — 7 артефактов с стратегиями копирования
- [ ] Создать `generate-checksums.sh` + запустить → `checksums.yaml`
- [ ] Создать `extension-points.yaml` — grep по протоколам/skills
- [ ] Создать 5 приоритетных MANIFEST.yaml (persistent-memory, skills, hooks)
- [ ] Модифицировать `setup.sh`: замена хардкод-копирования на manifest
- [ ] Модифицировать `seed/extensions/README.md`: ссылка на extension-points.yaml
- [ ] Модифицировать `setup/validate-template.sh`: проверка manifest + checksums

---

## Решения по ходу

> Секция для ad-hoc решений, принятых во время реализации.

| Дата | Решение | Причина |
|------|---------|---------|
| — | — | — |

---

*Реализация по ADR-005. Проект: https://github.com/users/abcdef0101/projects/8*
