#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_STRATEGIST_LIB_WAKATIME_LOADED:-}" ]]; then
  return 0
fi
readonly _STRATEGIST_LIB_WAKATIME_LOADED=1

function strategist_wakatime_load_env() {
  local env_file="$HOME/.config/aist/env"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
  fi
}

function strategist_wakatime_required() {
  [[ -n "${WAKATIME_API_KEY:-}" ]]
}

function strategist_wakatime_api_base() {
  printf '%s\n' 'https://wakatime.com/api/v1/users/current'
}

function strategist_wakatime_auth_header() {
  printf '%s' "$WAKATIME_API_KEY" | base64
}

function strategist_wakatime_fetch() {
  local encoded_token="${1}"
  local url="${2}"
  curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic ${encoded_token}" "${url}" 2>/dev/null
}

function strategist_wakatime_format_projects() {
  python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data:
    print('| (нет данных) | — |')
else:
    for p in sorted(data, key=lambda x: x.get('total_seconds', 0), reverse=True)[:10]:
        name = p.get('name', '?')
        text = p.get('text', '0 secs')
        print(f'| {name} | {text} |')
" 2>/dev/null || echo "| (ошибка парсинга) | — |"
}

function strategist_wakatime_format_languages() {
  python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data:
    print('| (нет данных) | — |')
else:
    for l in sorted(data, key=lambda x: x.get('total_seconds', 0), reverse=True)[:5]:
        name = l.get('name', '?')
        text = l.get('text', '0 secs')
        print(f'| {name} | {text} |')
" 2>/dev/null || echo "| (ошибка парсинга) | — |"
}

function strategist_wakatime_extract_total() {
  local response="${1}"
  echo "${response}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cumulative_total']['text'])" 2>/dev/null || echo "н/д"
}

function strategist_wakatime_extract_day_items() {
  local response="${1}"
  local key="${2}"
  echo "${response}" | python3 -c "import sys,json; d=json.load(sys.stdin); json.dump(d['data'][0].get('${key}',[]), sys.stdout)" 2>/dev/null || echo "[]"
}

function strategist_wakatime_aggregate_items() {
  local response="${1}"
  local key="${2}"
  echo "${response}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
agg = {}
for day in d.get('data', []):
    for item in day.get('${key}', []):
        name = item['name']
        agg[name] = agg.get(name, 0) + item.get('total_seconds', 0)
result = [{'name': k, 'total_seconds': v, 'text': f'{int(v//3600)}h {int((v%3600)//60)}m'} for k,v in agg.items()]
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]"
}
