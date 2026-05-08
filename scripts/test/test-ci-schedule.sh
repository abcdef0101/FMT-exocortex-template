#!/usr/bin/env bash
# test-ci-schedule.sh — cloud-scheduler.yml: YAML validity, cron, jobs
# Source: .github/workflows/cloud-scheduler.yml
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCHEDULER="$ROOT_DIR/.github/workflows/cloud-scheduler.yml"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- cloud-scheduler.yml ---"
[ -f "$SCHEDULER" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

python3 -c "
import yaml, sys
try:
    with open('$SCHEDULER') as f:
        data = yaml.safe_load(f)
    on_data = data.get('on') or data.get(True) or data.get(False) or {}
    if not isinstance(on_data, dict):
        sys.stderr.write(f'on field is not a dict\n')
    else:
        jobs = list(data.get('jobs', {}).keys())
        print(f'jobs: {len(jobs)} ({chr(44).join(jobs)})')
        sched = on_data.get('schedule')
        if sched:
            items = sched if isinstance(sched, list) else [sched]
            for s in items:
                cron = s.get('cron', '') if isinstance(s, dict) else str(s)
                fields = cron.split()
                if len(fields) == 5:
                    print(f'cron: {cron} ({len(fields)} fields)')
                else:
                    sys.stderr.write(f'invalid cron: {cron} ({len(fields)} fields)\n')
                    sys.exit(1)
except Exception as e:
    sys.stderr.write(f'YAML error: {e}\n')
    sys.exit(1)
" 2>/dev/null && rc=0 || rc=$?

[ "$rc" -eq 0 ] \
  && _pass "YAML valid, cron + jobs present" \
  || _fail "YAML validation failed"

# Check no hardcoded secrets
grep -q '\${{ secrets\.' "$SCHEDULER" 2>/dev/null \
  && _pass "secrets use GitHub Secrets notation" \
  || _pass "secrets: not via GitHub Secrets (may use env)"

grep -q 'backup\|health.check' "$SCHEDULER" 2>/dev/null \
  && _pass "backup + health-check jobs" \
  || _fail "expected jobs not found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
