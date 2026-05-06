# IWE: справочник для бота

> Краткая справка по Intellectual Work Environment (IWE) для поиска и ответов бота.
> Полная установка: [SETUP-GUIDE.md](SETUP-GUIDE.md)
>
> **Source-of-truth:** Pack-сущности платформы (доступны через Gateway `iwe-knowledge`):
> - `DP.IWE.001` — что такое IWE, зачем, архитектура
> - `DP.IWE.002` — шаблон и установка, пререквизиты, FAQ, безопасность
> - `DP.EXOCORTEX.001` — архитектура экзокортекса (3 слоя, модули)
> - `DP.ARCH.002` — тиры T0-T4 + TM1-TM3 + TA1-TA4 + TD1
> - `DP.ROLE.001` — реестр ИИ-ролей

---

## Что такое IWE

IWE (Intellectual Work Environment) — интеллектуальная рабочая среда. Описывается через пять видов (FPF A.7: **Роль → Метод → Рабочий продукт**):

| Вид | Что | Примеры |
|-----|-----|---------|
| **Системы** | Программы с 4D-границами | Claude Code, Telegram-бот, MCP-серверы, WakaTime, Git, экзокортекс (файлы), Neon DB |
| **Описания** | Знания, загружаемые в системы | FPF/SPF/ZP, Pack-сущности, промпты ролей, содержимое экзокортекса |
| **Роли** | Функция, не исполнитель | Стратег (R1) ← Claude, Экстрактор (R2), Синхронизатор (R8), Пользователь ← Человек |
| **Методы** | Процедуры «как делать» | Протокол ОРЗ, Capture-to-Pack, ArchGate, KE, Note-Review |
| **Рабочие продукты** | Что производится | DS-strategy, Pack-документы, DS-проекты, события ЦД |

Полная архитектурная модель: [LEARNING-PATH.md § 1.2](LEARNING-PATH.md). Source-of-truth: `DP.IWE.001` (через Gateway: `knowledge_search("IWE архитектура")`).

---

## Что нужно для установки

### Обязательно
- macOS, Linux или Windows (через WSL)
- Git + GitHub аккаунт + GitHub CLI (`gh`)
- Node.js v18+ и npm
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- Подписка Anthropic: **Claude Pro** ($20/мес) — рекомендуется для старта. При необходимости — **Claude Max** (~$100/мес) для работы без ограничений на количество сообщений.

### Опционально
- VS Code (рекомендуется) или любой другой редактор с терминалом. Claude Code — CLI, работает в любом терминале (Terminal.app, iTerm2 и др.). VS Code удобен: редактор + терминал + расширение Claude Code в одном окне
- Telegram (@aist_me_bot) — для заметок
- WakaTime — трекинг рабочего времени

---

## Как установить IWE

**Время установки: 30–60 минут** (зависит от опыта с терминалом).

Подробное руководство с пошаговыми инструкциями (включая как открыть терминал, установить все зависимости и что делать, если что-то пошло не так): **[SETUP-GUIDE.md](SETUP-GUIDE.md)**

Результат установки:
- Форк шаблона экзокортекса в твой GitHub
- CLAUDE.md и persistent-memory/ — настроенные под тебя
- Стратег (ИИ-агент) — в автоматическом расписании
- DS-strategy — приватный репо для планирования

---

## Доступ к знаниям (MCP)

MCP (Model Context Protocol) — протокол, через который Claude Code подключается к базе знаний платформы. Один Gateway-сервер агрегирует все бэкенды:

| Сервер | Что даёт | Инструменты |
|--------|---------|-------------|
| **iwe-knowledge** (Gateway: `mcp.aisystant.com/mcp`) | Поиск по Pack-репо, руководствам, DS (~5400 документов) + цифровой двойник | `knowledge_search`, `knowledge_get_document`, `knowledge_list_sources`, `dt_read_digital_twin`, `dt_write_digital_twin`, `dt_describe_by_path` |

> Поиск по руководствам: `knowledge_search("запрос", source_type="guides")`.

MCP подключается через https://claude.ai/settings/connectors (см. SETUP-GUIDE §1.3b). Проверка: `/mcp` в Claude Code → серверы Connected. Попроси «Найди документы про принципы» — Claude использует `knowledge_search`.

---

## Три роли в IWE

> В шаблоне экзокортекса **3 роли**, доступные сразу: Стратег, Экстрактор, Синхронизатор. Платформа поддерживает 21 роль — они подключаются по мере развития системы.
> Полный реестр ролей: `DP.ROLE.001` (через Gateway: `knowledge_search("реестр ролей агентов")`).

### Стратег (R1)
Планирование и рефлексия. Каждое утро (Вт-Вс) формирует план дня из коммитов вчера. Понедельник — подготовка к недельной сессии. Вечером (23:00) — разбор заметок из Telegram.

Ручной запуск (в терминале или встроенном терминале VS Code):
```bash
bash ~/IWE/FMT-exocortex-template/roles/strategist/scripts/strategist.sh day-plan
```

### Экстрактор (R2)
Извлечение знаний в Pack-репозитории. 4 сценария: session-close (при закрытии сессии), on-demand (по запросу), inbox-check (каждые 3 часа), knowledge-audit (аудит полноты).

Всегда предлагает, никогда не пишет без одобрения (human-in-the-loop).

Установка (в терминале): `bash ~/IWE/FMT-exocortex-template/roles/extractor/install.sh`

### Синхронизатор (R8)
Центральный диспетчер (bash, не ИИ). Управляет расписанием всех ролей, отправляет уведомления в Telegram, делает ночной обзор кода.

Установка (в терминале): `bash ~/IWE/FMT-exocortex-template/roles/synchronizer/install.sh`

---

## Протокол ОРЗ (ежедневная работа)

Каждая сессия в Claude Code — три стадии:

**Открытие.** Даёшь задание → Claude проверяет WP Gate (есть ли в плане недели?). Если нет — предлагает добавить. Объявляет роль, метод, оценку.

**Работа.** Claude выполняет задачу. На рубежах фиксирует знания: «Capture: [что] → [куда]».

**Закрытие.** Скажи «закрывай» → Claude коммитит, пушит, обновляет память, бэкапит.

---

## Память (3 слоя)

| Слой | Файл | Когда загружается |
|------|------|-------------------|
| Оперативная | `workspaces/<ws>/memory/MEMORY.md` | Всегда (авто-контекст) |
| Правила | `CLAUDE.md` | Всегда (авто-контекст) |
| Справочная | `persistent-memory/*.md` | По запросу |

MEMORY.md — личные (текущие задачи, РП недели). Редактируется каждую сессию.
`DS-strategy/docs/WP-REGISTRY.md` — полный реестр всех РП от последнего к первому (DP.WP.015). Обновляется на Close при изменении статуса.
Остальные persistent-memory/*.md — платформенные. Обновляются из upstream через `update.sh` (ADR-005: manifest-driven + checksum enforcement).

---

## Обновление IWE

```bash
cd ~/IWE/FMT-exocortex-template
bash update.sh --check   # проверить без применения (exit 0=up-to-date, 1=changes)
bash update.sh --apply   # применить обновление
```

Обновляются: CLAUDE.md, persistent-memory/ (кроме MEMORY.md), промпты ролей, скрипты.
НЕ трогаются: MEMORY.md, DS-strategy/, routing.md, личные настройки.

---

## Telegram-заметки

Бот @aist_me_bot принимает заметки:
- `.Текст заметки` (точка + текст)
- `.` + ответ/пересылка на сообщение

Заметки попадают в `DS-strategy/inbox/fleeting-notes.md`. Стратег разбирает вечером (Note-Review).

---

## Частые проблемы

**Claude Code не запускается** — проверь подписку Anthropic и `claude --version`. Начинать можно с Pro plan ($20/мес). При необходимости — Max (~$100/мес).

**Стратег не формирует план** — macOS: `launchctl list | grep strategist`. Linux: `systemctl --user list-timers | grep exocortex-strategist`. Если нет — `bash roles/strategist/install.sh --workspace-dir <путь> --claude-path $(which claude) --timezone-hour <час>`.

**MEMORY.md не загружается** — проверь путь: `~/IWE/FMT-exocortex-template/workspaces/<ws>/memory/MEMORY.md`. Workspace = имя из `workspaces/CURRENT_WORKSPACE`.

**DS-strategy не создан** — вручную: `mkdir -p ~/IWE/DS-strategy/{current,inbox,docs,archive} && cd ~/IWE/DS-strategy && git init`.

**Заметки не приходят из Telegram** — проверь подписку в @aist_me_bot. Формат: точка + текст (`.Моя заметка`).

**MCP не работает (Claude не ищет по базе)** — проверь подключение: `/mcp` в Claude Code. Серверы должны быть Connected. Если их нет — добавь через https://claude.ai/settings/connectors (см. SETUP-GUIDE §1.3b).

**Как настроить уведомления в Telegram** — создай `~/.config/aist/env`:
```bash
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-id"
```

---

## Глоссарий

| Термин | Значение |
|--------|---------|
| IWE | Intellectual Work Environment — интеллектуальная рабочая среда |
| Экзокортекс | Подсистема памяти IWE (CLAUDE.md + MEMORY.md + persistent-memory/) |
| Pack | Предметная база знаний (source-of-truth для домена) |
| DS-strategy | Личный стратегический хаб (приватный репо) |
| WP Gate | Проверка: есть ли задача в плане недели? |
| ОРЗ | Открытие → Работа → Закрытие (три стадии сессии) |
| Capture | Фиксация знания по ходу работы |
| Platform-space | Стандартные файлы, обновляются из upstream |
| User-space | Личные файлы, никогда не затираются |
| Routing | Таблица маршрутизации знаний (куда класть captures) |
| Marp | Инструмент для создания слайдов из Markdown. Workflow: `.md` → предпросмотр (VS Code) → PDF/HTML (`marp --pdf`). Используется для слайдоментов |
| MCP | Model Context Protocol — доступ Claude Code к внешним базам знаний |
| iwe-knowledge | Gateway MCP-сервер (`mcp.aisystant.com/mcp`): поиск по Pack, руководствам, DS + цифровой двойник |

---

## Дополнительные материалы

**В этом репо:**
- [SETUP-GUIDE.md](SETUP-GUIDE.md) — пошаговая установка (от нуля до работающего IWE)
- [LEARNING-PATH.md](LEARNING-PATH.md) — полный путь изучения: принципы, протоколы, агенты, Pack, SOTA
- [principles-vs-skills.md](principles-vs-skills.md) — почему навыков недостаточно: принципы и генеративная иерархия

**В Pack (через Gateway `knowledge_search`):**
- `DP.IWE.001` — что такое IWE, зачем, 5 архитектурных видов, сравнения (vs экзокортекс, vs агенты, vs second brain)
- `DP.IWE.002` — шаблон и установка: пререквизиты, стоимость, роли, ОРЗ, FAQ, безопасность
- `DP.EXOCORTEX.001` — модульный экзокортекс: 3 слоя, template-sync, standard/personal
- `DP.ARCH.002` — тиры T0-T4 + TM1-TM3 + TA1-TA4 + TD1: что доступно на каждом уровне
- `DP.ROLE.001` — полный реестр ИИ-ролей (21 роль)

---

## Смена AI-провайдера (Claude Code ↔ OpenCode)

### Claude Code → OpenCode

1. Установи OpenCode: `npm install -g opencode-ai`
2. Создай `AGENTS.md` (аналог `CLAUDE.md` для OpenCode):
   ```bash
   cp CLAUDE.md AGENTS.md
   ```
3. Переключи переменные:
   ```bash
   export AI_CLI=opencode
   export AI_CLI_MODEL="deepseek/deepseek-v4-pro"
   export AI_CLI_API_KEY="sk-..."
   ```
4. Для кастомного API-эндпоинта:
   ```bash
   export AI_CLI_BASE_URL="https://my-api.company.com/v1"
   export AI_CLI_MODEL="custom/my-model"
   ```
5. Создай headless-агента для cron-сценариев:
   ```bash
   opencode agent create strategist-test --tools "Read,Write,Edit,Glob,Grep,Bash"
   ```

### OpenCode → Claude Code

1. Установи Claude Code: `npm install -g @anthropic-ai/claude-code`
2. `CLAUDE.md` уже есть — Claude читает его автоматически
3. Верни переменные:
   ```bash
   export AI_CLI=claude
   export AI_CLI_API_KEY="$ANTHROPIC_API_KEY"
   ```

### Проверка

```bash
source scripts/ai-cli-wrapper.sh
ai_cli_run "say exactly: provider check OK" --bare --budget 0.10
```

Подробнее: [ADR-008](../docs/adr/ADR-008-ai-provider-abstraction.md)
