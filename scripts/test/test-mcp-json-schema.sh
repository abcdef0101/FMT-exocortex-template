#!/usr/bin/env bash
# test-mcp-json-schema.sh — MCP server JSON validation (§14, workflow-full.md)
# Source: seed/extensions/mcps/*.json
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
MCP_DIR="${MCP_DIR:-$ROOT_DIR/seed/extensions/mcps}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- MCP JSON files ---"
if [ ! -d "$MCP_DIR" ]; then
  _pass "no MCP directory (seed without extensions)"
  exit 0
fi

json_files=$(find "$MCP_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null || true)
if [ -z "$json_files" ]; then
  _pass "no MCP JSON files (extensions not configured)"
  exit 0
fi

count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name=$(basename "$f")
  count=$((count + 1))

  python3 -c "
import sys, json
try:
    d = json.load(open('$f'))
    servers = d.get('mcpServers', {})
    if not servers:
        sys.stderr.write('no mcpServers key\n')
        sys.exit(1)
    for sname, sdata in servers.items():
        stype = sdata.get('type', '')
        if stype not in ('http', 'sse', 'stdio'):
            sys.stderr.write(f'server {sname}: unknown type {stype}\n')
            sys.exit(1)
        if stype == 'http' and 'url' not in sdata:
            sys.stderr.write(f'server {sname}: http type missing url\n')
            sys.exit(1)
    print(f'valid: {len(servers)} servers')
except json.JSONDecodeError as e:
    sys.stderr.write(f'invalid JSON: {e}\n')
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f'validation error: {e}\n')
    sys.exit(1)
" 2>/dev/null && rc=0 || rc=$?

  if [ "$rc" -eq 0 ]; then
    _pass "$name: valid"
  else
    _fail "$name: invalid"
  fi
done <<< "$json_files"

echo "  MCP files: $count checked"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
