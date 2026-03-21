#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_DT_COLLECTORS_LIB_LOADED:-}" ]]; then
  return 0
fi
readonly _DT_COLLECTORS_LIB_LOADED=1

function dt_collect_wakatime() {
  local date_value="${1}"

  if [[ -z "${WAKATIME_API_KEY:-}" ]]; then
    echo "{}"
    return 0
  fi

  local encoded api today_resp week_resp month_resp d7 d30
  encoded=$(printf '%s' "$WAKATIME_API_KEY" | base64)
  api="https://wakatime.com/api/v1/users/current"
  today_resp=$(curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic ${encoded}" "$api/summaries?start=${date_value}&end=${date_value}" 2>/dev/null || echo "{}")
  d7=$(iwe_date_days_ago 7)
  week_resp=$(curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic ${encoded}" "$api/summaries?start=${d7}&end=${date_value}" 2>/dev/null || echo "{}")
  d30=$(iwe_date_days_ago 30)
  month_resp=$(curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic ${encoded}" "$api/summaries?start=${d30}&end=${date_value}" 2>/dev/null || echo "{}")

  python3 -c "
import json
def safe_load(s):
    try: return json.loads(s)
    except Exception: return {}
today = safe_load('''${today_resp}''')
week = safe_load('''${week_resp}''')
month = safe_load('''${month_resp}''')
def total_seconds(resp):
    try: return int(resp['cumulative_total']['seconds'])
    except Exception: return 0
def active_days(resp):
    try: return sum(1 for d in resp.get('data', []) if d.get('grand_total', {}).get('total_seconds', 0) > 0)
    except Exception: return 0
def top_items(resp, key, limit=10):
    agg = {}
    for day in resp.get('data', []):
        for item in day.get(key, []):
            name = item.get('name', '?')
            agg[name] = agg.get(name, 0) + item.get('total_seconds', 0)
    return sorted([{'name': k, 'seconds': int(v)} for k, v in agg.items()], key=lambda x: x['seconds'], reverse=True)[:limit]
print(json.dumps({
    'coding_seconds_today': total_seconds(today),
    'coding_seconds_7d': total_seconds(week),
    'coding_seconds_30d': total_seconds(month),
    'coding_active_days_30d': active_days(month),
    'top_projects': top_items(month, 'projects', 10),
    'top_languages': top_items(month, 'languages', 5),
    'top_editors': top_items(month, 'editors', 5),
}))
" 2>/dev/null || echo "{}"
}

function dt_collect_git() {
  local workspace_dir="${1}"
  WORKSPACE_FOR_DT_COLLECT="${workspace_dir}" python3 - <<'PY' 2>/dev/null || echo "{}"
import json, os, subprocess, re
from datetime import datetime, timedelta
workspace = os.environ['WORKSPACE_FOR_DT_COLLECT']
repos = []
for name in sorted(os.listdir(workspace)):
    path = os.path.join(workspace, name)
    if os.path.isdir(os.path.join(path, '.git')):
        repos.append((name, path))
def git_count(path, since):
    try:
        out = subprocess.check_output(['git','-C',path,'log',f'--since={since}','--oneline','--no-merges'], stderr=subprocess.DEVNULL, text=True).strip()
        return len(out.split('\n')) if out else 0
    except Exception:
        return 0
def git_shortstat(path, since):
    try:
        out = subprocess.check_output(['git','-C',path,'log',f'--since={since}','--shortstat','--no-merges','--format='], stderr=subprocess.DEVNULL, text=True).strip()
        files = ins = dels = 0
        for line in out.split('\n'):
            line = line.strip()
            if not line: continue
            m_f = re.search(r'(\d+) files? changed', line)
            m_i = re.search(r'(\d+) insertions?\(\+\)', line)
            m_d = re.search(r'(\d+) deletions?\(-\)', line)
            if m_f: files += int(m_f.group(1))
            if m_i: ins += int(m_i.group(1))
            if m_d: dels += int(m_d.group(1))
        return files,ins,dels
    except Exception:
        return 0,0,0
now = datetime.now(); d7=(now - timedelta(days=7)).strftime('%Y-%m-%d'); d30=(now - timedelta(days=30)).strftime('%Y-%m-%d')
commits_today = sum(git_count(p, '24 hours ago') for _, p in repos)
commits_7d = sum(git_count(p, d7) for _, p in repos)
commits_30d = sum(git_count(p, d30) for _, p in repos)
repos_7d=[]
for name,path in repos:
    c=git_count(path,d7)
    if c>0: repos_7d.append({'name': name, 'commits': c})
repos_7d.sort(key=lambda x:x['commits'], reverse=True)
files_7d = ins_7d = dels_7d = 0
for _,path in repos:
    f,i,d = git_shortstat(path,d7)
    files_7d += f; ins_7d += i; dels_7d += d
print(json.dumps({'commits_today': commits_today,'commits_7d': commits_7d,'commits_30d': commits_30d,'repos_active_7d': repos_7d[:15],'files_changed_7d': files_7d,'lines_added_7d': ins_7d,'lines_removed_7d': dels_7d}))
PY
}

function dt_collect_sessions() {
  local session_log="${1}"
  local workspace_dir="${2}"
  SESSION_LOG_PATH="${session_log}" WORKSPACE_FOR_DT_COLLECT="${workspace_dir}" python3 - <<'PY' 2>/dev/null || echo "{}"
import json, os, re, subprocess
from datetime import datetime, timedelta
log_path = os.environ['SESSION_LOG_PATH']; workspace = os.environ['WORKSPACE_FOR_DT_COLLECT']
now = datetime.now(); d7 = now - timedelta(days=7); total = recent = 0
if os.path.exists(log_path):
    with open(log_path) as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith('#'): continue
            total += 1
            m = re.match(r'(\d{4}-\d{2}-\d{2})', line)
            if m:
                try:
                    dt = datetime.strptime(m.group(1), '%Y-%m-%d')
                    if dt >= d7: recent += 1
                except Exception:
                    pass
git_sessions_7d = 0
for name in os.listdir(workspace):
    path = os.path.join(workspace, name)
    if os.path.isdir(os.path.join(path, '.git')):
        try:
            out = subprocess.check_output(['git','-C',path,'log','--since=7 days ago','--format=%aI','--no-merges'], stderr=subprocess.DEVNULL, text=True).strip()
            if out:
                dates = set(line[:10] for line in out.split('\n') if line)
                git_sessions_7d += len(dates)
        except Exception:
            pass
print(json.dumps({'claude_sessions_total': max(total, git_sessions_7d), 'claude_sessions_7d': max(recent, git_sessions_7d)}))
PY
}

function dt_collect_wp() {
  local memory_file="${1}"
  MEMORY_FILE_FOR_DT="${memory_file}" python3 - <<'PY' 2>/dev/null || echo "{}"
import json, os
memory_path = os.environ['MEMORY_FILE_FOR_DT']; done = in_progress = 0
if os.path.exists(memory_path):
    with open(memory_path) as f:
        in_table = False
        for line in f:
            if '| # | РП' in line or '| --- |' in line:
                in_table = True
                continue
            if in_table:
                if line.strip() == '' or line.startswith('---'):
                    in_table = False
                    continue
                lower = line.lower()
                if '| done' in lower or '~~done~~' in lower or '| ✅ |' in line: done += 1
                elif 'in_progress' in lower: in_progress += 1
print(json.dumps({'wp_completed_total': done, 'wp_in_progress_count': in_progress}))
PY
}

function dt_collect_health() {
  local state_dir="${1}"
  STATE_DIR_FOR_DT="${state_dir}" python3 - <<'PY' 2>/dev/null || echo "{}"
import json, os
from datetime import datetime
state_dir = os.environ['STATE_DIR_FOR_DT']; today = datetime.now().strftime('%Y-%m-%d'); health = 'green'; uptime = 0
if os.path.isdir(state_dir):
    markers = [f for f in os.listdir(state_dir) if not f.startswith('.')]
    dates = set()
    for marker in markers:
        parts = marker.rsplit('-', 3)
        if len(parts) >= 3:
            date_part = '-'.join(parts[-3:])
            if len(date_part) == 10: dates.add(date_part)
    uptime = len(dates)
    expected = ['code-scan', 'strategist-morning']
    missing = [task for task in expected if not any(task in marker and today in marker for marker in markers)]
    if len(missing) > 0: health = 'yellow'
    if len(missing) > 1: health = 'red'
print(json.dumps({'scheduler_health': health, 'exocortex_uptime_days': uptime}))
PY
}
