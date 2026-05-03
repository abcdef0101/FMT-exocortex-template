# Smoke Test Checklist

> Ручные проверки, которые нельзя автоматизировать (требуют AI-агента, сети, GitHub auth).

## SMOKE-1: Day Open → Day Close полный цикл

**Требует:** Claude Code, настроенный workspace.

| # | Шаг | Ожидаемый результат |
|---|-----|-------------------|
| 1 | `claude` → «открой день» | `/day-open` загружен, DayPlan создан |
| 2 | Проверить `current/DayPlan.md` | Файл существует, WP-* блоки в формате `<details>` |
| 3 | Выполнить 1-2 задачи из DayPlan | — |
| 4 | «закрой день» | `/day-close` загружен, TodoWrite выполнен |
| 5 | Проверить `archive/day-plans/` | DayPlan перемещён, итоги записаны |
| 6 | Проверить `MEMORY.md` | Обновлён после day-close |

## SMOKE-2: Week Close с memory audit

**Требует:** Claude Code, минимум 2 дня данных в workspace.

| # | Шаг | Ожидаемый результат |
|---|-----|-------------------|
| 1 | «закрой неделю» | `/week-close` загружен |
| 2 | Проверить `archive/week-reports/` | Отчёт за неделю создан |
| 3 | Проверить `archive/week-plans/` | WeekPlan перемещён |
| 4 | Проверить аудит ADR | `docs/adr/` статусы актуальны |

## SMOKE-3: MCP-сервер подключение через Gateway

**Требует:** подписка «Бесконечное развитие», браузер для Ory OAuth.

| # | Шаг | Ожидаемый результат |
|---|-----|-------------------|
| 1 | `claude` → `/mcp` | Список MCP-серверов показан |
| 2 | Проверить `iwe-knowledge` | Статус: connected |
| 3 | «загрузи FPF A.7» | FPF-референс загружен через knowledge MCP |

## SMOKE-4: Роль auto-install (launchd/systemd)

**Требует:** macOS или Linux с systemd.

| # | Шаг | Ожидаемый результат |
|---|-----|-------------------|
| 1 | `bash setup.sh` (полный режим) | Роли установлены |
| 2 | `launchctl list \| grep strategist` (macOS) или `systemctl --user list-timers \| grep exocortex` (Linux) | Стратег в расписании |
| 3 | Дождаться утреннего запуска | DayPlan создан автоматически |

## SMOKE-5: GitHub repo create + push

**Требует:** `gh` CLI с авторизацией.

| # | Шаг | Ожидаемый результат |
|---|-----|-------------------|
| 1 | `bash setup.sh` (полный режим, свежий workspace) | DS-strategy создан на GitHub |
| 2 | Проверить `https://github.com/<user>/DS-strategy` | Репозиторий существует, приватный |
| 3 | Проверить `https://github.com/<user>/DS-agent-workspace` | Репозиторий существует, приватный |

---

## Результаты последнего прогона

| Smoke | Дата | Результат | Комментарий |
|-------|------|-----------|------------|
| SMOKE-1 | — | — | — |
| SMOKE-2 | — | — | — |
| SMOKE-3 | — | — | — |
| SMOKE-4 | — | — | — |
| SMOKE-5 | — | — | — |
