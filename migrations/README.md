# Миграционный фреймворк

> ADR-005 §4: идемпотентные скрипты для breaking changes

## Конвенции

### Именование

```
migrations/{version}-{component}-{description}.sh
```

Примеры:
- `0.25.0-compress-protocol-close.sh`
- `0.24.0-add-collapsible-dayplan.sh`
- `0.18.0-remove-author-only.sh`

### Структура скрипта

Каждый миграционный скрипт обязан:

1. **Pre-condition**: проверить что миграция действительно нужна (idempotency gate)
2. **Backup**: создать `.backup` перед любым изменением
3. **Apply**: выполнить изменение
4. **Post-condition**: валидировать результат
5. **Log**: записать в `.claude/logs/migrations.log`

### Идемпотентность

Миграция может быть запущена повторно без побочных эффектов. Pre-condition гарантирует что изменения применяются только если они ещё не применены.

### Порядок выполнения

Миграции сортируются по имени (версии) и выполняются последовательно. Каждая миграция запускается только если её версия > локально применённой.

### Логирование

Формат лога (`.claude/logs/migrations.log`):
```
2026-05-03T10:00:00Z [OK] 0.25.0-compress-protocol-close.sh
2026-05-03T10:00:01Z [SKIP] 0.24.0-add-collapsible-dayplan.sh (already applied)
2026-05-03T10:00:02Z [FAIL] 0.18.0-remove-author-only.sh (backup failed)
```

## Шаблон

См. `migrations/_template.sh` — копируй и заполняй для новых миграций.
