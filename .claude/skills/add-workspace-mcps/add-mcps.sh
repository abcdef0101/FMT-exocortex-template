#!/usr/bin/env bash
# Добавляет MCP-серверы из extensions/mcps/*.json активного workspace в scope project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

CURRENT_WS_LINK="$ROOT/workspaces/CURRENT_WORKSPACE"

if [ ! -L "$CURRENT_WS_LINK" ] && [ ! -d "$CURRENT_WS_LINK" ]; then
  echo "ERROR: CURRENT_WORKSPACE не установлен. Запусти скилл iwe-workspace." >&2
  exit 1
fi

WS_DIR="$(cd "$CURRENT_WS_LINK" && pwd)"
MCPS_DIR="$WS_DIR/extensions/mcps"

if [ ! -d "$MCPS_DIR" ]; then
  echo "Директория $MCPS_DIR не существует — нечего добавлять."
  exit 0
fi

added=0
skipped=0

for json_file in "$MCPS_DIR"/*.json; do
  [ -f "$json_file" ] || continue

  basename_file="$(basename "$json_file")"

  if ! python3 -c "import json,sys; json.load(open('$json_file'))" 2>/dev/null; then
    echo "SKIP (невалидный JSON): $basename_file"
    skipped=$((skipped + 1))
    continue
  fi

  has_mcp_servers=$(python3 -c "
import json, sys
data = json.load(open('$json_file'))
if not isinstance(data, dict) or 'mcpServers' not in data:
    sys.exit(1)
servers = data['mcpServers']
if not isinstance(servers, dict) or len(servers) == 0:
    sys.exit(1)
print('ok')
" 2>/dev/null || echo "")

  if [ "$has_mcp_servers" != "ok" ]; then
    echo "SKIP (нет mcpServers): $basename_file"
    skipped=$((skipped + 1))
    continue
  fi

  entries=$(python3 -c "
import json
data = json.load(open('$json_file'))
for name, config in data['mcpServers'].items():
    print(f'{name}\t{json.dumps(config)}')
" "$json_file")

  while IFS=$'\t' read -r name config; do
    echo "Добавление: $name (из $basename_file) [scope=local]"
    # cd в WS_DIR чтобы claude писал в реальный .mcp.json, а не через симлинк в корне проекта
    (cd "$WS_DIR" && claude mcp add-json --scope project "$name" "$config")
    added=$((added + 1))
  done <<<"$entries"
done

echo ""
echo "Готово: добавлено серверов — $added, пропущено файлов — $skipped."
