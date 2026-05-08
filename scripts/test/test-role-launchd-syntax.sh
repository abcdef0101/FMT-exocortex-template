#!/usr/bin/env bash
# test-role-launchd-syntax.sh — валидация launchd plist файлов
# Source: roles/*/scripts/launchd/*.plist (4 files)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- launchd plist files ---"
plist_files=$(find "$ROOT_DIR/roles" -name "*.plist" -type f 2>/dev/null || true)
if [ -z "$plist_files" ]; then
  _fail "no plist files found"
  exit $FAIL
fi

count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name="${f#$ROOT_DIR/}"
  count=$((count + 1))

  python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    tree = ET.parse('$f')
    root = tree.getroot()
    d = {k.text: v.text if len(v) == 0 else [c.text for c in v] for k, v in [(el.find('key'), el) for el in root.findall('dict/key/..') if el.find('key') is not None]}
    labels = [v.text for v in root.findall('.//key') if v.text == 'Label']
    progs = [v.text for v in root.findall('.//key') if v.text == 'ProgramArguments']
    has_label = len(labels) > 0
    has_prog = len(progs) > 0
    has_schedule = any(v.text in ('StartInterval','StartCalendarInterval') for v in root.findall('.//key'))
    if not has_label: sys.stderr.write('missing Label key\n'); sys.exit(1)
    if not has_prog: sys.stderr.write('missing ProgramArguments\n'); sys.exit(1)
    if not has_schedule: sys.stderr.write('missing schedule key\n'); sys.exit(1)
    print(f'valid: Label present, ProgramArguments present, schedule present')
except ET.ParseError as e:
    sys.stderr.write(f'XML parse error: {e}\n')
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f'error: {e}\n')
    sys.exit(1)
" 2>/dev/null && rc=0 || rc=$?

  if [ "$rc" -eq 0 ]; then
    _pass "$name: valid plist"
  else
    _fail "$name: invalid plist"
  fi
done <<< "$plist_files"

echo "  plist files: $count checked"
[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
