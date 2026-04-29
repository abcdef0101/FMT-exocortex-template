#!/usr/bin/env bash
# Fetch WakaTime stats for Strategist prompts
# Usage: fetch-wakatime.sh [--workspace-dir DIR] [today|day|week]
#   mode: "today" — today's summary, all projects (for day-close)
#         "day"   — yesterday's summary (for day-plan)
#         "week"  — current + previous week (for week-review)
#
# Конфигурация:
#   --workspace-dir DIR   — явный путь к workspace (default: FMT_DIR/workspaces/CURRENT_WORKSPACE)
#   API_KEY_WAKATIME      — API-ключ в $WORKSPACE_DIR/.env

set -euo pipefail

readonly API="https://wakatime.com/api/v1/users/current"
ENCODED=""
FMT_DIR=""
WORKSPACE_DIR=""
CLI_WORKSPACE_DIR=""
WAKATIME_API_KEY=""
BUDGET_H=""

show_usage() {
    echo "Использование: fetch-wakatime.sh [--workspace-dir DIR] [--budget <часы>] [today|day|week|multiplier]"
    echo "  Режим по умолчанию: today"
    echo "  --workspace-dir DIR — использовать указанный workspace"
    echo "  --budget <часы>     — бюджет закрытых РП (для режима multiplier), десятичные часы"
}

resolve_fmt_dir() {
    local dir
    dir="$(cd "$(dirname "$0")" && pwd)"
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        echo "Cannot resolve script directory from \$0=$0" >&2
        exit 1
    fi
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/update-manifest.json" ] || [ -d "$dir/workspaces" ]; then
            FMT_DIR="$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    echo "Cannot find FMT repo root (no update-manifest.json or workspaces/ found)" >&2
    exit 1
}

resolve_workspace() {
    if [ -n "$CLI_WORKSPACE_DIR" ]; then
        if [ ! -d "$CLI_WORKSPACE_DIR" ]; then
            echo "Workspace directory not found: $CLI_WORKSPACE_DIR" >&2
            exit 1
        fi
        WORKSPACE_DIR="$CLI_WORKSPACE_DIR"
    else
        WORKSPACE_DIR="$FMT_DIR/workspaces/CURRENT_WORKSPACE"
    fi
}

load_env() {
    local env_file="$WORKSPACE_DIR/.env"
    if [ ! -f "$env_file" ]; then
        return 0
    fi
    while IFS='=' read -r key value; do
        value="${value#\"}"
        value="${value%\"}"
        case "$key" in
            API_KEY_WAKATIME) WAKATIME_API_KEY="$value" ;;
        esac
    done < "$env_file"
}

# Cross-platform date offset: portable_date_offset <days_back> [format]
# Works on macOS (BSD date) and GNU/Linux
portable_date_offset() {
    local days="$1"
    local fmt="${2:-%Y-%m-%d}"
    date -v-${days}d +"$fmt" 2>/dev/null || date -d "$days days ago" +"$fmt" 2>/dev/null
}

waka_fetch() {
    local url="$1"
    curl -sf --max-time 10 --connect-timeout 5 \
        -H "Authorization: Basic ${ENCODED}" "${url}" 2>/dev/null
}

format_projects() {
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

format_languages() {
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

main() {
    local mode="today"
    CLI_WORKSPACE_DIR=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --workspace-dir)
                if [ $# -lt 2 ]; then
                    echo "--workspace-dir requires an argument" >&2; exit 1
                fi
                CLI_WORKSPACE_DIR="$2"
                shift 2
                ;;
            --budget)
                if [ $# -lt 2 ]; then
                    echo "--budget requires an argument" >&2; exit 1
                fi
                BUDGET_H="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            today|day|week|multiplier)
                mode="$1"
                shift
                ;;
            *)
                echo "Неизвестный аргумент: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done

    resolve_fmt_dir
    resolve_workspace
    load_env

    if [ -z "${WAKATIME_API_KEY:-}" ]; then
        echo "WAKATIME_API_KEY not set" >&2
        exit 0
    fi

    ENCODED=$(echo -n "$WAKATIME_API_KEY" | base64)

    case "$mode" in
        "today")
            local TODAY RESPONSE TOTAL PROJECTS_JSON LANGS_JSON
            TODAY=$(date +%Y-%m-%d)
            RESPONSE=$(waka_fetch "${API}/summaries?start=${TODAY}&end=${TODAY}") || RESPONSE=""

            TOTAL=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cumulative_total']['text'])" 2>/dev/null || echo "н/д")
            PROJECTS_JSON=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); json.dump(d['data'][0].get('projects',[]), sys.stdout)" 2>/dev/null || echo "[]")
            LANGS_JSON=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); json.dump(d['data'][0].get('languages',[]), sys.stdout)" 2>/dev/null || echo "[]")

            cat <<EOF
## WakaTime: сегодня ($TODAY)

**Общее время (все проекты):** $TOTAL

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_JSON" | format_projects)

**По языкам:**

| Язык | Время |
|------|-------|
$(echo "$LANGS_JSON" | format_languages)
EOF
            ;;

        "day")
            local YESTERDAY RESPONSE TOTAL PROJECTS_JSON LANGS_JSON
            YESTERDAY=$(portable_date_offset 1)
            RESPONSE=$(waka_fetch "${API}/summaries?start=${YESTERDAY}&end=${YESTERDAY}") || RESPONSE=""

            TOTAL=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cumulative_total']['text'])" 2>/dev/null || echo "н/д")
            PROJECTS_JSON=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); json.dump(d['data'][0].get('projects',[]), sys.stdout)" 2>/dev/null || echo "[]")
            LANGS_JSON=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); json.dump(d['data'][0].get('languages',[]), sys.stdout)" 2>/dev/null || echo "[]")

            cat <<EOF
## WakaTime: вчера ($YESTERDAY)

**Общее время:** $TOTAL

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_JSON" | format_projects)

**По языкам:**

| Язык | Время |
|------|-------|
$(echo "$LANGS_JSON" | format_languages)
EOF
            ;;

        "week")
            local DOW DAYS_SINCE_MON MON_THIS TODAY MON_PREV SUN_PREV
            local RESP_THIS RESP_PREV TOTAL_THIS TOTAL_PREV
            local PROJECTS_THIS PROJECTS_PREV LANGS_THIS

            DOW=$(date +%u)
            DAYS_SINCE_MON=$((DOW - 1))
            MON_THIS=$(portable_date_offset "${DAYS_SINCE_MON}")
            TODAY=$(date +%Y-%m-%d)
            MON_PREV=$(portable_date_offset "$((DAYS_SINCE_MON + 7))")
            SUN_PREV=$(portable_date_offset "$((DAYS_SINCE_MON + 1))")

            RESP_THIS=$(waka_fetch "${API}/summaries?start=${MON_THIS}&end=${TODAY}") || RESP_THIS=""
            RESP_PREV=$(waka_fetch "${API}/summaries?start=${MON_PREV}&end=${SUN_PREV}") || RESP_PREV=""

            TOTAL_THIS=$(echo "$RESP_THIS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cumulative_total']['text'])" 2>/dev/null || echo "н/д")
            TOTAL_PREV=$(echo "$RESP_PREV" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cumulative_total']['text'])" 2>/dev/null || echo "н/д")

            PROJECTS_THIS=$(echo "$RESP_THIS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
agg = {}
for day in d.get('data', []):
    for p in day.get('projects', []):
        name = p['name']
        agg[name] = agg.get(name, 0) + p.get('total_seconds', 0)
result = [{'name': k, 'total_seconds': v, 'text': f'{int(v//3600)}h {int((v%3600)//60)}m'} for k,v in agg.items()]
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]")

            PROJECTS_PREV=$(echo "$RESP_PREV" | python3 -c "
import sys, json
d = json.load(sys.stdin)
agg = {}
for day in d.get('data', []):
    for p in day.get('projects', []):
        name = p['name']
        agg[name] = agg.get(name, 0) + p.get('total_seconds', 0)
result = [{'name': k, 'total_seconds': v, 'text': f'{int(v//3600)}h {int((v%3600)//60)}m'} for k,v in agg.items()]
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]")

            LANGS_THIS=$(echo "$RESP_THIS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
agg = {}
for day in d.get('data', []):
    for l in day.get('languages', []):
        name = l['name']
        agg[name] = agg.get(name, 0) + l.get('total_seconds', 0)
result = [{'name': k, 'total_seconds': v, 'text': f'{int(v//3600)}h {int((v%3600)//60)}m'} for k,v in agg.items()]
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]")

            cat <<EOF
## WakaTime: статистика рабочего времени

### Текущая неделя ($MON_THIS — $TODAY)

**Общее время:** $TOTAL_THIS

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_THIS" | format_projects)

**По языкам:**

| Язык | Время |
|------|-------|
$(echo "$LANGS_THIS" | format_languages)

### Предыдущая неделя ($MON_PREV — $SUN_PREV)

**Общее время:** $TOTAL_PREV

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_PREV" | format_projects)

**Сравнение:** текущая $TOTAL_THIS vs предыдущая $TOTAL_PREV
EOF
            ;;

        "multiplier")
            if [ -z "${BUDGET_H:-}" ]; then
                echo "--budget <часы> обязателен для режима multiplier" >&2
                exit 1
            fi

            local TODAY RESPONSE TOTAL_SECS WAKA_H WAKA_M WAKA_LABEL BUDGET_LABEL MULT
            TODAY=$(date +%Y-%m-%d)
            RESPONSE=$(waka_fetch "${API}/summaries?start=${TODAY}&end=${TODAY}") || RESPONSE=""

            TOTAL_SECS=$(echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
secs = sum(day.get('grand_total', {}).get('total_seconds', 0) for day in d.get('data', []))
print(int(secs))
" 2>/dev/null || echo "0")

            WAKA_H=$((TOTAL_SECS / 3600))
            WAKA_M=$(( (TOTAL_SECS % 3600) / 60 ))
            WAKA_LABEL="${WAKA_H}ч ${WAKA_M}мин"

            BUDGET_LABEL=$(python3 -c "
h = float('$BUDGET_H')
whole = int(h)
mins = int(round((h - whole) * 60))
if mins:
    print(f'{whole}ч {mins}мин')
else:
    print(f'{whole}ч')
" 2>/dev/null || echo "${BUDGET_H}ч")

            MULT=$(python3 -c "
waka = $TOTAL_SECS / 3600
budget = float('$BUDGET_H')
if waka > 0:
    print(f'{budget / waka:.1f}x')
else:
    print('н/д')
" 2>/dev/null || echo "н/д")

            cat <<EOF
| Метрика | Значение |
|---------|----------|
| **WakaTime (физическое время)** | ${WAKA_LABEL} |
| **Бюджет закрыт (оценки РП)** | ~${BUDGET_LABEL} |
| **Мультипликатор дня** | **${MULT}** |

> Формула: Бюджет закрыт / WakaTime.
EOF
            ;;
    esac
}

main "$@"
