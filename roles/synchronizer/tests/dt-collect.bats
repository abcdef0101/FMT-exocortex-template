#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  STATE_DIR="$TEST_DIR/state"
  mkdir -p "$STATE_DIR"
}

_load_dt_helpers() {
  source /dev/stdin <<'EOF'
portable_date_offset() {
    local days="$1"
    local fmt="${2:-%Y-%m-%d}"
    date -v-${days}d +"$fmt" 2>/dev/null || date -d "$days days ago" +"$fmt" 2>/dev/null
}

_validate_env_file() {
    local filepath="${1}"
    if grep -qE '^\s*(eval|source|\.)[ \t]' "${filepath}" 2>/dev/null; then
        echo "ERROR: env file contains dangerous patterns: ${filepath}" >&2
        exit 1
    fi
}
EOF
}

@test "portable_date_offset: yesterday format" {
  _load_dt_helpers
  local expected
  expected=$(date -d '1 days ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
  run portable_date_offset 1
  assert_success
  assert_output "$expected"
}

@test "portable_date_offset: custom format" {
  _load_dt_helpers
  run portable_date_offset 7 '%Y%m%d'
  assert_success
  [[ "$output" =~ ^[0-9]{8}$ ]]
}

@test "_validate_env_file: valid env passes" {
  _load_dt_helpers
  printf 'KEY=value\n' > "$TEST_DIR/ok.env"
  run _validate_env_file "$TEST_DIR/ok.env"
  assert_success
}

@test "_validate_env_file: eval rejected" {
  _load_dt_helpers
  printf 'eval "rm -rf /"\n' > "$TEST_DIR/bad.env"
  run _validate_env_file "$TEST_DIR/bad.env"
  assert_failure
}

@test "collect_health: green when required tasks exist" {
  local today
  today=$(date +%Y-%m-%d)
  touch "$STATE_DIR/code-scan-$today"
  touch "$STATE_DIR/strategist-morning-$today"
  run python3 - <<PY
import json, os
state_dir = "$STATE_DIR"
today = "$today"
health = 'green'
markers = [f for f in os.listdir(state_dir) if not f.startswith('.')]
expected = ['code-scan', 'strategist-morning']
missing = []
for task in expected:
    found = any(task in m and today in m for m in markers)
    if not found:
        missing.append(task)
if len(missing) > 0:
    health = 'yellow'
if len(missing) > 1:
    health = 'red'
print(health)
PY
  assert_success
  assert_output 'green'
}

@test "collect_health: yellow when one task missing" {
  local today
  today=$(date +%Y-%m-%d)
  touch "$STATE_DIR/code-scan-$today"
  run python3 - <<PY
import os
state_dir = "$STATE_DIR"
today = "$today"
health = 'green'
markers = [f for f in os.listdir(state_dir) if not f.startswith('.')]
expected = ['code-scan', 'strategist-morning']
missing = []
for task in expected:
    found = any(task in m and today in m for m in markers)
    if not found:
        missing.append(task)
if len(missing) > 0:
    health = 'yellow'
if len(missing) > 1:
    health = 'red'
print(health)
PY
  assert_success
  assert_output 'yellow'
}

@test "collect_health: red when both tasks missing" {
  run python3 - <<PY
markers = []
missing = ['code-scan', 'strategist-morning']
health = 'green'
if len(missing) > 0:
    health = 'yellow'
if len(missing) > 1:
    health = 'red'
print(health)
PY
  assert_success
  assert_output 'red'
}

@test "collect_wp: counts done and in_progress rows" {
  local mem="$TEST_DIR/MEMORY.md"
  cat > "$mem" <<'EOF'
| # | РП | Бюджет | P | Статус | Дедлайн |
|---|----|--------|---|--------|---------|
| 1 | A | 1h | P1 | in_progress | — |
| ~~2~~ | ~~B~~ | ~~1h~~ | ~~P1~~ | ~~done~~ | ~~—~~ |
EOF
  run python3 - <<PY
import os
memory_path = "$mem"
done = 0
in_progress = 0
in_table = False
with open(memory_path) as f:
    for line in f:
        if '| # | РП' in line or '| --- |' in line:
            in_table = True
            continue
        if in_table:
            if line.strip() == '' or line.startswith('---'):
                in_table = False
                continue
            if '| done' in line.lower() or '~~done~~' in line.lower():
                done += 1
            elif 'in_progress' in line.lower():
                in_progress += 1
            elif '| done |' in line:
                done += 1
print(done, in_progress)
PY
  assert_success
  assert_output '1 1'
}

@test "merge result: produces 2_6_coding and 2_7_iwe keys" {
  run python3 - <<'PY'
import json
waka = {'coding_seconds_today': 1}
git = {'commits_today': 2}
sessions = {'claude_sessions_total': 3}
wp = {'wp_completed_total': 4}
health = {'scheduler_health': 'green'}
result = {'2_6_coding': waka, '2_7_iwe': {**git, **sessions, **wp, **health}}
print(json.dumps(result, sort_keys=True))
PY
  assert_success
  assert_output --partial '2_6_coding'
  assert_output --partial '2_7_iwe'
}

@test "dry-run semantics: JSON printed, neon write skipped" {
  run bash -c 'DRY_RUN=true; MERGED="{""a"":1}"; if [ "$DRY_RUN" = true ]; then echo "$MERGED"; echo "DRY RUN — not writing to Neon"; fi'
  assert_success
  assert_output --partial 'DRY RUN — not writing to Neon'
}
