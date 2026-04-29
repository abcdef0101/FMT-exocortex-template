---
name: wakatime
description: "WakaTime статистика рабочего времени. today — за сегодня (используется в day-close и мультипликаторе IWE), day — вчера (для day-plan), week — текущая и предыдущая неделя. multiplier --budget <ч> — таблица мультипликатора IWE."
argument-hint: "[today|day|week|multiplier [--budget <часы>]]"
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/scripts/fetch-wakatime.sh" *)
---

Запусти скрипт и выведи результат пользователю без изменений:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/fetch-wakatime.sh" ${ARGUMENTS:-today}
```

Если `ARGUMENTS` не передан — использовать режим `today` по умолчанию.

## Режимы

| Режим | Пример | Описание |
|-------|--------|----------|
| `today` | `/wakatime` | Сегодня: итого + проекты + языки |
| `day` | `/wakatime day` | Вчера: итого + проекты + языки |
| `week` | `/wakatime week` | Текущая и предыдущая неделя |
| `multiplier` | `/wakatime multiplier --budget 4.5` | Таблица мультипликатора IWE (требует `--budget`) |

Для `multiplier`: `--budget` — суммарный бюджет закрытых РП в часах (десятичное число, напр. `3.5`).
