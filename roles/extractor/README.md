# Экстрактор (Knowledge Extractor, R2)

> Извлекает, формализует и маршрутизирует знания в Pack-репозитории и DS docs/.

## Что делает

При закрытии сессии или по запросу — находит знания (паттерны, различения, методы, ошибки), формализует и предлагает записать в правильное место. **Два выхода routing:** доменное знание → Pack (по шаблону SPF), реализационное знание → DS docs/ (сценарии, процессы, данные). Пользователь всегда одобряет перед записью.

## Сценарии

| Сценарий | Триггер | Режим |
|----------|---------|-------|
| **Session-Close** | Закрытие сессии (протокол Close) | Интерактивный |
| **On-Demand** | «Запиши это в Pack» | Интерактивный |
| **Knowledge Audit** | «Аудит Pack» / ежемесячно | Интерактивный |
| **Inbox-Check** | launchd / systemd каждые 3ч (опционально) | Headless (отчёт) |

## Когда подключать

- Создал первый Pack (PACK-{твоя-область})
- Работаешь с Claude Code регулярно (≥3 сессии/неделю)
- Хочешь автоматически фиксировать знания

## Установка

### 1. Настрой маршрутизацию

Отредактируй `config/routing.md` — добавь свои Pack'и:

```markdown
| Домен | Pack | Префикс | Путь |
|-------|------|---------|------|
| Мой домен | PACK-my-domain | MD | {{WORKSPACE_DIR}}/PACK-my-domain/pack/my-domain/ |
```

### 2. (Опционально) Установи автоматический inbox-check

```bash
cd roles/extractor
bash install.sh --workspace-dir /path/to/workspace --root-dir /path/to/root --agent-ai-path $(which claude)
# Опционально: --namespace my-workspace (по умолчанию — имя директории workspace)
```

Это установит launchd/systemd-агент для проверки inbox каждые 3 часа.

### 3. Ручной запуск

```bash
# Inbox-check (без launchd)
bash scripts/extractor.sh --root-dir /path/to/root --workspace my-workspace --agent-ai-path $(which claude) inbox-check

# Knowledge Audit
bash scripts/extractor.sh --root-dir /path/to/root --workspace my-workspace --agent-ai-path $(which claude) audit
```

## Как работает

```
Knowledge Extraction Pipeline:

  Обнаружение → Классификация → Маршрутизация → Формализация → Валидация → Одобрение → Запись

  1. Найти знания (captures + пропущенные инсайты)
  2. Определить тип (entity, distinction, method, fm, wp, rule)
  3. Определить: domain или implementation? (тест доменности)
     ├─ domain → Pack по домену (routing.md §1-4)
     └─ implementation → DS docs/ по системе (routing.md §5)
  4. Создать файл: Pack → шаблон SPF; DS → шаблон docs/
  5. Проверить: нет ли дубликатов и противоречий
  6. Показать Extraction Report пользователю
  7. Записать только одобренное
```

## Файлы

| Файл | Назначение |
|------|-----------|
| `config/routing.md` | Таблицы маршрутизации (Pack'и, типы, директории) |
| `config/feedback-log.md` | Лог отклонённых кандидатов (не предлагать повторно) |
| `prompts/session-close.md` | Промпт: экстракция при закрытии сессии |
| `prompts/on-demand.md` | Промпт: экстракция по запросу |
| `prompts/inbox-check.md` | Промпт: headless проверка inbox |
| `prompts/knowledge-audit.md` | Промпт: аудит Pack'ов |
| `scripts/extractor.sh` | Скрипт запуска (аналог strategist.sh) |
| `scripts/launchd/` | launchd plist для inbox-check |
| `scripts/systemd/` | systemd service/timer для inbox-check |

## Принципы

1. **Human-in-the-loop:** Экстрактор предлагает, не записывает без одобрения
2. **Один пайплайн:** Все сценарии используют classify → route → formalize → validate
3. **Тест универсальности:** Можно использовать в другом контексте? Нет → governance, не экстрагируй
4. **Lazy reading:** Inbox-check читает только целевой Pack, не все сразу

---

*Source-of-truth: DP.AISYS.013 (PACK-digital-platform)*
