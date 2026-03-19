# Покрытие тестами

Состояние на 2026-03-19.

## Итог

- Все tracked shell-скрипты (`*.sh`) в репозитории имеют прямое тестовое покрытие.
- Полный прогон Bats: **227/227**.
- Проверка markdown-ссылок: **включена в тестовый набор**.
- Embedded git repos в `test_helper/` устранены, helpers централизованы в `tests/test_helper/`.

## Карта тестов

| Файл тестов | Кол-во | Что покрывает |
|---|---:|---|
| `tests/setup.bats` | 26 | `setup.sh` |
| `tests/update.bats` | 11 | `update.sh` |
| `tests/validate-template.bats` | 9 | `setup/validate-template.sh` |
| `tests/install-scripts.bats` | 6 | `roles/*/install.sh` |
| `tests/hooks.bats` | 10 | `.claude/hooks/*` |
| `tests/setup-calendar.bats` | 8 | `setup/optional/setup-calendar.sh` |
| `tests/markdown-links.bats` | 1 | валидность локальных markdown-ссылок |
| `roles/strategist/tests/strategist.bats` | 13 | `strategist.sh` |
| `roles/strategist/tests/fetch-wakatime.bats` | 10 | `fetch-wakatime.sh` |
| `roles/strategist/tests/cleanup-processed-notes.bats` | 13 | `cleanup-processed-notes.sh` |
| `roles/extractor/tests/extractor.bats` | 16 | `extractor.sh` |
| `roles/synchronizer/tests/scheduler.bats` | 18 | `scheduler.sh` |
| `roles/synchronizer/tests/notify.bats` | 10 | `notify.sh` |
| `roles/synchronizer/tests/code-scan.bats` | 10 | `code-scan.sh` |
| `roles/synchronizer/tests/daily-report.bats` | 17 | `daily-report.sh` |
| `roles/synchronizer/tests/dt-collect.bats` | 10 | `dt-collect.sh` |
| `roles/synchronizer/tests/remaining-sync.bats` | 10 | `sync-files.sh`, `video-scan.sh`, `templates/*` |
| `roles/auditor/tests/auditor.bats` | 18 | `auditor` contract + prompts |
| `roles/verifier/tests/verifier.bats` | 11 | `verifier` contract + prompts |

## Что считается покрытым

- entrypoint-скрипты
- install-скрипты ролей
- shell hooks
- notification templates
- optional setup scripts
- markdown link integrity

## Инфраструктура

- Общие helpers: `tests/test_helper/`
- Используемые библиотеки:
  - `tests/test_helper/bats-support`
  - `tests/test_helper/bats-assert`
  - `tests/test_helper/bats-file`
- Role-local `test_helper/` больше не содержат собственных git repos.

## Запуск

Полный набор:

```bash
bats tests/*.bats roles/*/tests/*.bats
```

Точечно:

```bash
bats tests/update.bats
bats roles/synchronizer/tests/*.bats
```

Проверка markdown-ссылок отдельно:

```bash
python3 tests/validate_markdown_links.py
```

## Примечания

- Тесты в основном контрактные и поведенческие; они не измеряют line coverage.
- Для shell-скриптов основной упор сделан на:
  - аргументы и usage-path
  - dry-run / skip-path
  - файловые побочные эффекты
  - merge / sync / install сценарии
  - изоляцию окружения и mock внешних команд
