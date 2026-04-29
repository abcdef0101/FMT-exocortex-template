# Close Protocol Architecture

> **Тип:** Architectural reference
> **valid_from:** 2026-04-25
> **Сфера:** Протоколы Close (Quick/Day/Week) — слоистая модель, authority, контракт каждого слоя.

---

## Краткая модель

```
триггер → enforcement/entry → protocol router → protocol executor → protocol algorithm → helpers/templates/extensions → verification
```

Для Day Close конкретно:

```
пользовательский триггер → hook / alias → day-close skill → helper script day-close.sh → verifier
```

`run-protocol` не владеет самим Day Close. Он владеет только общей механикой пошагового исполнения.

---

## Authority map

| Вариант Close | Semantic authority | Местонахождение |
|---|---|---|
| Quick Close (сессия) | `protocol-close.md` (inline) | `persistent-memory/protocol-close.md` |
| Day Close | `day-close/SKILL.md` | `.claude/skills/day-close/SKILL.md` |
| Week Close | `week-close/SKILL.md` | `.claude/skills/week-close/SKILL.md` |
| Generic execution rules | `run-protocol/SKILL.md` | `.claude/skills/run-protocol/SKILL.md` |
| Mechanical day-close operations | `day-close.sh` | `.claude/skills/day-close/scripts/day-close.sh` |

---

## Слои

### Слой 0. Intent / Trigger

**Файлы:** `CLAUDE.md`, пользовательский запрос.

**За что отвечает:** Определить, что произошло событие «закрытие». Пользователь пишет «закрываю день», «закрывай», «итоги недели» — это триггеры. Automation доводит систему до weekly close — тоже триггер.

**За что не отвечает:** Не исполняет протокол, не содержит бизнес-логику.

---

### Слой 1. Enforcement / Entry

**Файлы:** `.claude/hooks/close-gate-reminder.sh`.

**За что отвечает:** Насильно отправить агента в правильную точку входа. Не дать ему начать «закрывать день вручную», прочитав protocol-файл и пропустив шаги. Hook инжектит БЛОКИРУЮЩУЮ инструкцию: «ПЕРВОЕ И ЕДИНСТВЕННОЕ действие = вызвать skill».

**За что не отвечает:** Не содержит алгоритм Day Close, не решает, что делать.

---

### Слой 2. Contract / Router

**Файлы:** `persistent-memory/protocol-close.md`.

**За что отвечает:** Объявить, что у Close есть 3 масштаба (Session, Day, Week). Задать маршрутизацию: Session → Quick Close inline, Day → `day-close/SKILL.md`, Week → `week-close/SKILL.md`. Зафиксировать общие инварианты (Quick Close ≠ Day Close, принцип TodoWrite enforcement).

**За что не отвечает:** Не должен хранить полный Day/Week Close алгоритм. Иначе он снова становится «толстым protocol-файлом», который агент читает напрямую и пропускает шаги.

**Правило:** protocol-файл ≤ 150 строк. Quick Close — inline (он короткий). Day/Week Close — только ссылка на skill.

---

### Слой 3. Generic Executor

**Файлы:** `.claude/skills/run-protocol/SKILL.md`.

**За что отвечает:** Общая машина исполнения протоколов. Понять, какой протокол вызван. Если у протокола есть свой SKILL.md — брать полный алгоритм оттуда. Загрузить extensions (before/after/checks). Превратить алгоритм в TodoWrite-задачи. Следить: один шаг in_progress, последовательность обязательна. Запустить финальную верификацию.

**За что не отвечает:** Не знает бизнес-логику конкретного Day Close. Не решает, что писать в WeekPlan или MEMORY.md.

**Аналог:** workflow engine — движок исполнения, а не содержание протокола.

---

### Слой 4. Protocol Authority

**Файлы:** `.claude/skills/day-close/SKILL.md`, `.claude/skills/week-close/SKILL.md`.

**За что отвечает:** Полный алгоритм конкретного протокола. Порядок шагов, переходы, бизнес-правила обновления WeekPlan/MEMORY.md/DayPlan, checklist протокола, условия (day_close_after_enabled, lesson_rotation). Именно здесь знание: что считать итогом дня, когда обновлять carry-over, что входит в compact dashboard, что проверять перед commit.

**За что не отвечает:** Не должен быть alias-оберткой без алгоритма (это была ошибка upstream). Не должен делегировать обратно в protocol-close.md (circular delegation).

**Принцип:** Это single semantic authority протокола. Если алгоритм описан не здесь — его нет.

---

### Слой 5. Reference / Templates

**Файлы:** `persistent-memory/templates-dayplan.md`, `persistent-memory/navigation.md`.

**За что отвечает:** Хранить шаблоны (DayPlan, compact dashboard, WeekPlan, итоги дня) и тяжелые reference-блоки, чтобы не раздувать skill-файлы. Skill ссылается на шаблон («запиши секцию по шаблону из templates-dayplan.md»), но не несет его внутри себя.

**За что не отвечает:** Не исполняет шаги, не содержит бизнес-правил.

**Почему отдельный слой:** Алгоритм протокола и шаблоны артефактов — разные типы знаний. Смешивание = раздувание skill на 300+ строк.

---

### Слой 6. Mechanical Helpers

**Файлы:** `.claude/skills/day-close/scripts/day-close.sh`.

**За что отвечает:** Выполнить детерминированные операции, которые лучше делает shell, а не LLM: backup memory (commit + push MEMORY.md, day-rhythm-config.yaml и др. в workspace-репо). Свести механические операции в один вызов из skill.

**За что не отвечает:** Не решает, закрыт ли день. Не пишет в WeekPlan/MEMORY.md. Не определяет, какой шаг сейчас идет. Не содержит бизнес-правил.

**Принцип:** Helper = руки протокола, но не мозг. Вызывается skill-ом на конкретном шаге (шаг 4 в day-close/SKILL.md). Не является entrypoint, не вызывается пользователем напрямую.

---

### Слой 7. Extension / Config

**Файлы:** `extensions/day-close.*.md`, `extensions/week-close.*.md`, `params.yaml`.

**За что отвечает:** Кастомизация поведения без редактирования платформенного ядра. Before-расширения (утренние ритуалы), multiplier-расширение (мультипликатор IWE), after-расширения (рефлексия), checks (дополнительные проверки), параметры (lesson_rotation, day_close_after_enabled).

**За что не отвечает:** Не должен становиться вторым владельцем протокола. Extension вставляет шаг, но не переписывает ownership.

**Принцип:** Core логика — в платформенном слое (skills). Пользовательские отклонения — отдельно (extensions/). `update.sh` не трогает extensions.

---

### Слой 8. Verification

**Файлы:** `roles/verifier/README.md`, `roles/verifier/prompts/verify-wp-acceptance.md`, чеклисты внутри skill-файлов.

**За что отвечает:** Подтвердить, что протокол завершен формально корректно. Проверить checklist: все ли шаги выполнены, есть ли commit, обновлен ли MEMORY.md. Исполняется sub-agent Haiku R23 (context isolation).

**За что не отвечает:** Не исполняет Day Close. Не решает, какие у Day Close бизнес-правила. Не становится вторым оркестратором.

**Принцип:** Verification = контроль, а не исполнение.

---

### Слой 9. Legacy / Historical

**Файлы:** `roles/strategist/prompts/day-close.md`, `roles/strategist/prompts/day-plan.md`, часть `roles/strategist/README.md`.

**За что отвечает:** Историческая справка и миграционный след. Показывает, как было раньше, для контекста при отладке.

**За что не отвечает:** Не должен использоваться как runtime authority. Если legacy-слой снова начинает исполняться — возникает второй authority path, и архитектура ломается.

**Признаки проблем:** deprecated-промпт всё ещё executable через strategist.sh → второй runtime path → drift.

---

## End-to-end потоки

### Quick Close (сессия)

```
триггер «закрывай» → hook → protocol-close.md (inline Quick Close) → commit/push + WP context + KE + MEMORY.md → checklist → verifier (Haiku R23)
```

Quick Close исполняется inline в protocol-close.md. Skill не нужен — протокол короткий (~3 мин, 4 шага). TodoWrite не используется намеренно (минимальный барьер).

### Day Close

```
триггер «закрываю день» → hook → /day-close или /run-protocol close day → run-protocol загружает extensions → day-close/SKILL.md (full algorithm via TodoWrite) → шаг 7: .claude/skills/day-close/scripts/day-close.sh (backup memory) + extensions/linear-sync.sh (optional) → checks + commit/push → compact dashboard → verifier (Haiku R23)
```

### Week Close

```
триггер «закрываю неделю» → hook → /week-close или /run-protocol week-close → run-protocol загружает extensions → week-close/SKILL.md (full algorithm via TodoWrite) → commit/push → verifier (Haiku R23)
```

---

## Правило «что можно / что нельзя» по слоям

| Слой | Можно | Нельзя |
|---|---|---|
| 0. Intent | Распознавать триггеры | Исполнять протокол |
| 1. Enforcement | Блокировать неправильный вход | Содержать бизнес-логику |
| 2. Router | Маршрутизировать, декларировать инварианты | Хранить полный алгоритм Day/Week Close |
| 3. Executor | Управлять TodoWrite, загружать extensions | Знать бизнес-смысл конкретного протокола |
| 4. Authority | Владеть полным алгоритмом, бизнес-правилами | Быть alias-stub, делегировать обратно в router |
| 5. Templates | Хранить шаблоны, reference-данные | Исполнять шаги |
| 6. Helpers | Выполнять механические операции (backup memory) | Решать, закрыт ли протокол |
| 7. Extensions | Добавлять шаги, настраивать параметры | Переписывать ownership протокола |
| 8. Verification | Проверить формальную завершенность | Исполнять протокол |
| 9. Legacy | Хранить историческую справку | Использоваться как runtime authority |

---

## Практическое правило (одна строка)

- `protocol-close.md` отвечает за **что есть Close**
- `run-protocol` отвечает за **как протокол исполнять пошагово**
- `day-close/week-close SKILL.md` отвечают за **что именно делать в Day/Week Close**
- `.claude/skills/day-close/scripts/day-close.sh` отвечает за **как выполнить механические подшаги**
- `verifier` отвечает за **как подтвердить завершенность**
- `extensions/params` отвечают за **как адаптировать без поломки ядра**
