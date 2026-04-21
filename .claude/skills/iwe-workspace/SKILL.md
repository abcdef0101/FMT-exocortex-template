---
name: iwe-workspace
description: "Управление рабочими пространствами IWE: показать текущее, список доступных, переключить."
argument-hint: "[--set-workspace <name> | --get-workspaces]"
version: 1.0.0
---

# iwe-workspace

Управляет симлинкой `workspaces/CURRENT_WORKSPACE`.

## Параметры

| Аргумент | Действие |
|----------|---------|
| (нет) | Текущее пространство + список |
| `--get-workspaces` | Список доступных пространств |
| `--set-workspace <name>` | Переключить на `<name>` |

## Алгоритм

1. Прочитать `ARGUMENTS:`.

2. Если пусто или `list` → показать текущее и список:
   ```bash
   readlink workspaces/CURRENT_WORKSPACE 2>/dev/null | xargs basename 2>/dev/null || echo "(не установлено)"
   bash .claude/skills/iwe-workspace/workspace.sh --get-workspaces
   ```

3. Если передано имя `<name>` → переключить:
   ```bash
   bash .claude/skills/iwe-workspace/workspace.sh --set-workspace=<name>
   ```

4. Сообщить результат пользователю.
5. Если было переключение → вывести:
   > Workspace переключён. Выполни `/clear` чтобы перезагрузить контекст и MCP-конфигурацию нового workspace.
