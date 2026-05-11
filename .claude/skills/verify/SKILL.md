---
name: verify
description: Верификация артефакта по эталону из Pack. Загружает роль VR.R.001 (Верификатор) с context isolation — проверяет результат, а не процесс создания.
argument-hint: "[code|archgate|capture|wp|chain|adversarial|auto] [путь или описание]"
---

# Верификация артефакта

> **Роль:** VR.R.001 Верификатор (PACK-verification)
> **Принцип:** Context isolation (VR.SOTA.002) — проверяю результат по эталону, НЕ процесс создания.
> **Архитектура:** Ядро (Pack, фиксированное) + Контекст (переменный) — AS.D.004.

Аргументы: $ARGUMENTS

## Шаг 0. Определить тип проверки

| Аргумент | Тип | Что проверяет |
|----------|-----|---------------|
| `code` | Проверка кода | Качество кода: логика, edge cases, безопасность, coupling |
| `archgate` | Проверка реализации АрхГейта | Код соответствует ЭМОГССБ-оценке, принципы воплощены |
| `capture` | Проверка capture-candidate | UL, полнота, непротиворечивость с Pack |
| `wp` | Приёмка рабочего продукта | Критерии done из WP context file |
| `chain` | Data flow check | Прочитаны ли downstream consumers? Контракты совпадают? (CoVe stage 3) |
| `adversarial` | Scope & bias check | Scope определён анализом или выводом? Что НЕ прочитано? (Pre-mortem) |
| `auto` или пусто | Автоопределение | По типу файла и контексту сессии |

**Автоопределение:**
- Был АрхГейт в текущей сессии → `archgate`
- Указан путь к .py/.ts/.sh файлу → `code`
- Указан путь к Pack-сущности → `capture`
- Указан путь к WP context → `wp`
- Изменения >1 файла + cross-component → предложить `chain`
- После АрхГейта + код → предложить `adversarial`
- Не определился → спросить пользователя

## Шаг 1. Выполнить верификацию

### Перед запуском: убедись что definition-файлы агентов существуют

```bash
ls .claude/agents/verifier-*.md .opencode/agents/verifier-*.md 2>/dev/null || bash scripts/create-agents.sh
```

### Для каждого типа — механическая предпроверка + AI sub-agent

**`code`:**
1. `bash scripts/verify-chain-discovery.sh` — собрать affected symbols и consumers
2. Agent(verifier-code) — передать: diff + CLAUDE.md + чеклист code.
   Чеклист: логика, edge cases, безопасность, coupling. Модель: thinking.

**`archgate`:**
1. `bash scripts/verify-archgate-formal.sh <таблица>` — формальная проверка таблицы
2. Если (1) failed → вернуть ошибку, AI-часть не запускать
3. Agent(verifier-archgate) — передать: файлы реализации + таблица + принципы.
   Чеклист: код воплощает принципы? Каждое измерение подтверждено? Модель: pro.

**`capture`:**
1. `bash scripts/verify-capture-formal.sh <candidate> [manifest]` — формальная проверка
2. Если (1) failed → вернуть ошибку, AI-часть не запускать
3. Agent(verifier-capture) — передать: candidate + manifest + чеклист capture.
   Чеклист: UL соответствует Pack? Нет противоречий? Модель: thinking.

**`wp`:**
1. `bash scripts/verify-close.sh` — формальная проверка done-критериев (R23)
2. Если (1) failed → вернуть ошибку
3. Для качественной оценки содержания → Agent(verifier-archgate) или ручная рецензия (R25).
   Модель: pro.

**`chain` (CoVe — Chain-of-Verification, Meta ACL 2024):**
1. `bash scripts/verify-chain-discovery.sh` — поиск downstream consumers
2. Прочитать каждый consumer из вывода скрипта
3. Agent(verifier-chain) — передать: diff + consumers + чеклист chain.
   Чеклист chain:
   1. Прочитан ли каждый потребитель?
   2. Типы/формат output совпадают с ожиданиями потребителя?
   3. Переменные определены в том же scope? Env vars переданы явно?
   Модель: thinking.

**`adversarial` (Pre-mortem + Devil's Advocate, PROClaim 2026):**
1. `bash scripts/verify-adversarial-scope.sh "<список прочитанных файлов>"` — найти непрочитанные
2. Прочитать описание задачи (WP context или commit message)
3. Agent(verifier-adversarial) — передать: diff + unread files + task description + чеклист adversarial.
   Чеклист adversarial:
   1. Scope определён анализом или подогнан под вывод?
   2. Какие файлы НЕ прочитаны, но могут быть затронуты?
   3. Предположи 3 причины поломки в production.
   4. Альтернативные объяснения проблемы?
   5. Заявленный scope соответствует реальному?
   Модель: thinking.

## Шаг 2. Sub-agent: промпт

Sub-agent получает промпт с заполненными данными из шага 1.

**⛔ Sub-agent НЕ получает:**
- Историю обсуждения текущей сессии
- Задание создателя
- Промежуточные рассуждения

**Для `code`, `capture`, `wp`, `archgate`** — определить эталон:

| Тип артефакта | Эталон |
|---------------|--------|
| Pack-сущность | SPF pack-template + доменные принципы Pack |
| Описание метода | SPF process/07 + Pack |
| Код (DS) | CLAUDE.md репо + Pack-описания сервисов |
| Архитектурное решение | DP.ARCH.001 §7 (→ используй /archgate вместо /verify) |
| План (WeekPlan/DayPlan) | Протоколы Open/Close |

Если эталон не определяется → **СТОП.** Сообщи: «Эталон не найден. Нужен рецензент, не верификатор.»

**Для `chain`, `adversarial`** — эталон = сам код (downstream consumers, scope analysis). Чеклисты встроены в шаг 1.

## Шаг 3. Verdict

Sub-agent возвращает verdict:

```
## Verdict: [PASS / FAIL / CONDITIONAL]

**Контекст:** [тип проверки]
**Артефакт:** [что проверялось]
**Эталон:** [по чему проверялось]

### Несоответствия

| # | Severity | Файл | Строка | Что | Почему (reasoning) | Эталон |
|---|----------|------|--------|-----|-------------------|--------|
| 1 | критический / высокий / средний / низкий | path | N | описание | почему проблема | принцип/правило |

### Сводка

- **Критических:** N
- **Высоких:** N
- **Средних:** N
- **Низких:** N

### Рекомендация

[1-3 предложения]
```

**Правила verdict:**
- **PASS:** 0 критических, 0 высоких
- **CONDITIONAL:** 0 критических, ≥1 высоких
- **FAIL:** ≥1 критических

## Шаг 4. Показать пользователю

Вывести verdict. Пользователь решает:
- **Принять** → продолжить работу
- **Исправить** → внести изменения по рекомендациям
- **Отклонить verdict** → аргументировать почему (→ feedback для обучения)
