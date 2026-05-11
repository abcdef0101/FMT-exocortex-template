# ADR-014: Архитектура уведомлений — Observer + Adapter

**Статус:** Принято
**Дата:** 2026-05-11
**Контекст:** FMT-exocortex-template/scripts, roles/synchronizer (R8), PACK-digital-platform (DP.D.033)

---

## Контекст

Система уведомлений экзокортекса прошла через две реализации:

1. **Observer + Adapter** (origin/main): `scripts/notify.sh` — системный dispatcher с auto-discovered адаптерами (`scripts/adapters/`). Интерфейс: `<title> <message> [level]`. Роли source-ят shared library `lib-notify.sh`. Шаблоны сообщений — в директории каждой роли.
2. **Template/Source** (HEAD): `roles/synchronizer/scripts/notify.sh` — монолитный dispatcher, source-ящий шаблоны по имени агента. Интерфейс: `--workspace-dir --env-file <agent> <scenario>`. Адаптеры удалены, shared library удалена, тесты удалены.

Обе реализации сосуществовали в репозитории без явного архитектурного решения. Коммит `54d1420` ввёл Observer без ADR; коммиты `15d6cef` и позже заменили его на Template/Source также без ADR.

## Проблема

### Template/Source (HEAD) — структурные дефекты

1. **Связность dispatcher'а с доменом ролей.** `notify.sh` знает имена агентов (`strategist`, `extractor`), source-ит их шаблоны, вызывает `build_message(scenario)`. Dispatcher уровня платформы не должен знать доменную логику ролей.
2. **Нерасширяемость каналов.** Добавление нового канала (Slack, email) требует правки `send_telegram()` или дублирования логики в notify.sh.
3. **Отсутствие аудит-трейса.** Нет файлового лога уведомлений — невозможно диагностировать потерю сообщения.
4. **Нет уровней важности.** `note-review` canary (потеря данных) отправляется с тем же приоритетом, что и `day-plan` (информационное).
5. **Нет изоляции каналов.** Падение Telegram API прерывает весь скрипт (`set -e`).
6. **Дублирование кода.** Функция `notify()` скопирована в 4 ролевых скрипта.

### Почему Observer устраняет эти дефекты

| Дефект | Как Observer устраняет |
|--------|----------------------|
| Связность с доменом ролей | Dispatcher принимает title+message — не знает об агентах/сценариях |
| Нерасширяемость каналов | Новый канал = новый файл в `adapters/` |
| Нет аудит-трейса | `log.sh` адаптер пишет всегда, независимо от других каналов |
| Нет уровней | 4 уровня: info < notice < alert < critical, каждый адаптер фильтрует по min_level |
| Нет изоляции | Каждый адаптер — subshell `(...)` — падение одного不影响 остальные |
| Дублирование кода | `lib-notify.sh` с идемпотентной загрузкой |

## Решение

### Каноническая архитектура: Observer + Adapter

```
scripts/notify.sh
  └─ auto-discover scripts/adapters/*.sh
       ├─ log.sh       (min=info,    always enabled)
       ├─ telegram.sh  (min=notice,  TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID)
       ├─ slack.sh     (min=notice,  SLACK_WEBHOOK_URL, stub)
       └─ email.sh     (min=critical, IWE_EMAIL_TO, stub)
```

**Контракт dispatcher'а:**
```
scripts/notify.sh <title> <message> [level=info]
```

**Контракт адаптера:**
```bash
adapter_enabled()    # → 0 если канал доступен
adapter_min_level()  # → "info"|"notice"|"alert"|"critical"
adapter_send()       # получает title, message
```

**Контракт роли:**
```bash
source roles/shared/lib/lib-notify.sh
notify()            # → iwe_notify_local()
notify_telegram()   # → build message → scripts/notify.sh "Agent: scenario" "$msg" "level"
```

### Запрещённый паттерн

Source-шаблонов внутри dispatcher'а. Dispatcher не source-ит `templates/<agent>.sh`, не знает понятий «агент» и «сценарий». Формирование сообщения — ответственность роли.

### Уровни важности

| Уровень | Int | Пример |
|---------|-----|--------|
| `info` | 0 | Code scan: нет коммитов |
| `notice` | 1 | Day plan составлен, inbox-check завершён |
| `alert` | 2 | Не сработал canary, синхронизация упала |
| `critical` | 3 | Потеря данных, падение сервиса |

`telegram.sh` фильтрует: min_level = notice. `log.sh` пишет всё (min_level = info).

### Размещение файлов

```
scripts/
├── notify.sh                  # Observer dispatcher (системный модуль)
└── adapters/
    ├── telegram.sh
    ├── log.sh
    ├── slack.sh
    └── email.sh

lib/
├── lib-env.sh                 # iwe_find_repo_root, iwe_load_env_file, iwe_validate_env_file
└── lib-telegram.sh            # iwe_telegram_send()

roles/
├── shared/lib/lib-notify.sh   # iwe_notify_local(), iwe_notify_via_script()
├── strategist/scripts/templates/strategist.sh
├── extractor/scripts/templates/extractor.sh
├── synchronizer/scripts/templates/synchronizer.sh
├── verifier/scripts/templates/verifier.sh
└── auditor/scripts/templates/auditor.sh
```

## Последствия

### Положительные

- **Расширяемость:** Добавление Slack — файл `scripts/adapters/slack.sh` (без правки dispatcher'а или ролей).
- **Аудит:** `log.sh` даёт полный трейс всех уведомлений с таймстемпами, уровнями и заголовками.
- **Устойчивость:** Падение Telegram не ломает `log.sh` и не прерывает ролевой скрипт.
- **Тестируемость:** Adapter'ы тестируются изолированно (mock curl, mock env). Dispatcher тестируется без адаптеров.
- **Единая библиотека:** `lib-notify.sh` — один source-point для всех ролей.

### Отрицательные

- **+2 файла в lib/:** `lib-env.sh`, `lib-telegram.sh` — были удалены в HEAD, нужно восстановить.
- **+4 файла адаптеров:** `telegram.sh`, `log.sh`, `slack.sh`, `email.sh` — были удалены в HEAD.
- **Маршрутизация сообщений:** Роль теперь отвечает за вызов `build_message()` из своего шаблона, а не делегирует это dispatcher'у. Это +3 строки в `notify_telegram()` каждой роли.

### Миграция

1. Восстановить `scripts/notify.sh`, `scripts/adapters/`, `lib/lib-*.sh`, `roles/shared/lib/lib-notify.sh` из коммита `54d1420` (origin/main).
2. Вернуть шаблоны в `roles/<role>/scripts/templates/`.
3. Создать шаблоны для verifier (R23) и auditor (R24).
4. Заменить `notify()` и `notify_telegram()` во всех ролевых скриптах на вызовы из `lib-notify.sh`.
5. Удалить `roles/synchronizer/scripts/notify.sh` (монолит).
6. Восстановить `notify.bats` тесты.

---

*Связанные ADR:*
- ADR-002 (модульные роли — `notify.sh` был одной из точек hardcoded имён)
- ADR-005 (update delivery — post-update notify как один из шагов пайплайна)
