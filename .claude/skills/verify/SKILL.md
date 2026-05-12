---
name: verify
description: Верификация артефакта по эталону из Pack. Загружает роль R23 Верификатор с context isolation — проверяет результат, а не процесс создания.
argument-hint: "[code|archgate|capture|wp|chain|adversarial|auto] [путь или описание]"
---

# Верификация артефакта

> **Роль:** R23 Верификатор
> **Принцип:** Context isolation — проверяю результат по эталону, НЕ процесс создания.
> **Агенты:** verifier (sonnet) — code, capture, chain, adversarial; verifier-heavy (opus) — archgate, wp

Аргументы: $ARGUMENTS

## Шаг 0. Определить тип проверки

| Аргумент | Тип | Агент | Что проверяет |
|----------|-----|-------|---------------|
| `code` | Проверка кода | verifier | Качество кода: логика, edge cases, безопасность, coupling |
| `archgate` | Проверка реализации АрхГейта | verifier-heavy | Код соответствует ЭМОГССБ-оценке, принципы воплощены |
| `capture` | Проверка capture-candidate | verifier | UL, полнота, непротиворечивость с Pack |
| `wp` | Приёмка рабочего продукта | verifier-heavy | Критерии done из WP context file |
| `chain` | Data flow check | verifier | Прочитаны ли downstream consumers? Контракты совпадают? |
| `adversarial` | Scope & bias check | verifier | Scope определён анализом или выводом? Что НЕ прочитано? |
| `auto` или пусто | Автоопределение | (по типу) | По типу файла и контексту сессии |

**Автоопределение:**
- Был АрхГейт в текущей сессии → `archgate`
- Указан путь к .py/.ts/.sh файлу → `code`
- Указан путь к Pack-сущности → `capture`
- Указан путь к WP context → `wp`
- Изменения >1 файла + cross-component → предложить `chain`
- После АрхГейта + код → предложить `adversarial`
- Не определился → спросить пользователя

## Шаг 1. Механическая предпроверка

Выполни bash-скрипт для типа проверки. Если failed → вернуть ошибку, AI не запускать.

| Тип | Bash-скрипт |
|-----|------------|
| `code` | `bash scripts/verify-chain-discovery.sh` |
| `archgate` | `bash scripts/verify-archgate-formal.sh <таблица>` |
| `capture` | `bash scripts/verify-capture-formal.sh <candidate> [manifest]` |
| `wp` | `bash scripts/verify-close.sh` |
| `chain` | `bash scripts/verify-chain-discovery.sh` |
| `adversarial` | `bash scripts/verify-adversarial-scope.sh "<список прочитанных файлов>"` |

## Шаг 2. Запустить sub-agent

Вызови Task tool с нужным агентом. Передай в prompt:

1. **Тип проверки** (code/archgate/capture/wp/chain/adversarial)
2. **Результаты bash-предпроверки** (вывод скрипта из шага 1)
3. **Данные артефакта** (diff, файлы, таблица)
4. **Эталон** (см. таблицу ниже)

Агент сам загрузит нужный skill через skill tool и выполнит проверку.

| Тип артефакта | Эталон |
|---------------|--------|
| Pack-сущность | SPF pack-template + доменные принципы Pack |
| Описание метода | SPF process/07 + Pack |
| Код (DS) | CLAUDE.md репо + Pack-описания сервисов |
| Архитектурное решение | DP.ARCH.001 §7 |
| План (WeekPlan/DayPlan) | Протоколы Open/Close |
| chain/adversarial | Эталон = сам код (consumers, scope) |

Если эталон не определяется → **СТОП.** Сообщи: «Эталон не найден. Нужен рецензент, не верификатор.»

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

### Сводка
- Критических: N
- Высоких: N
- Средних: N
- Низких: N

### Рекомендация
[1-3 предложения]
```

**Правила verdict:**
- **PASS:** 0 критических, 0 высоких
- **CONDITIONAL:** 0 критических, >=1 высоких
- **FAIL:** >=1 критических

## Шаг 4. Показать пользователю

Вывести verdict. Пользователь решает:
- **Принять** → продолжить работу
- **Исправить** → внести изменения по рекомендациям
- **Отклонить verdict** → аргументировать почему (→ feedback для обучения)
