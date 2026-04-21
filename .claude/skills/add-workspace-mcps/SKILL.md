---
name: add-workspace-mcps
description: "Добавить MCP-серверы из extensions/mcps/*.json активного workspace в scope project."
version: 1.0.0
---

# add-workspace-mcps

Сканирует `<CURRENT_WORKSPACE>/extensions/mcps/*.json`, извлекает все `mcpServers` и регистрирует их через `claude mcp add-json --scope local`, запуская команду из директории workspace — чтобы не сломать симлинк `.mcp.json` в корне проекта.

## Когда использовать

- После переключения workspace (`iwe-workspace`), чтобы подключить его MCP-серверы.
- После добавления нового `*.json`-файла в `extensions/mcps/`.
- При первоначальной настройке workspace.

## Алгоритм

1. Запусти скрипт:
   ```bash
   bash .claude/skills/add-workspace-mcps/add-mcps.sh
   ```

2. Выведи результат пользователю.

3. Если скрипт завершился с ошибкой `CURRENT_WORKSPACE не установлен` — сообщи пользователю, что нужно сначала выбрать workspace через скилл `iwe-workspace`.

4. Если добавлено > 0 серверов — напомни:
   > MCP-серверы зарегистрированы в scope project. Перезапусти Claude Code (или выполни `/clear`), чтобы они стали активны.
