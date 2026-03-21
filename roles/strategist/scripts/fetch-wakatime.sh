#!/usr/bin/env bash
# Fetch WakaTime stats for Strategist prompts
# Targets: Linux, macOS
# Usage: fetch-wakatime.sh <mode>
#   mode: "day"  — yesterday's summary (for day-plan)
#         "week" — current + previous week (for week-review)

set -euo pipefail

# shellcheck source=lib/lib-platform.sh
source "$(cd "$(dirname "$0")/../../../" && pwd)/lib/lib-platform.sh"

# shellcheck source=roles/strategist/lib/lib-wakatime.sh
source "$(cd "$(dirname "$0")/../" && pwd)/lib/lib-wakatime.sh"

strategist_wakatime_load_env

if ! strategist_wakatime_required; then
    echo "WAKATIME_API_KEY not set"
    exit 0  # graceful — don't break strategist if no key
fi

ENCODED=$(strategist_wakatime_auth_header)
API=$(strategist_wakatime_api_base)

mode="${1:-day}"

case "$mode" in
    "day")
        # Yesterday's summary
        YESTERDAY=$(iwe_date_shift -1)
        RESPONSE=$(strategist_wakatime_fetch "$ENCODED" "$API/summaries?start=$YESTERDAY&end=$YESTERDAY")

        TOTAL=$(strategist_wakatime_extract_total "$RESPONSE")
        PROJECTS_JSON=$(strategist_wakatime_extract_day_items "$RESPONSE" projects)
        LANGS_JSON=$(strategist_wakatime_extract_day_items "$RESPONSE" languages)

        cat <<EOF
## WakaTime: вчера ($YESTERDAY)

**Общее время:** $TOTAL

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_JSON" | strategist_wakatime_format_projects)

**По языкам:**

| Язык | Время |
|------|-------|
$(echo "$LANGS_JSON" | strategist_wakatime_format_languages)
EOF
        ;;

    "week")
        # Current week (Mon-today) + previous week
        # Current week
        DOW=$(date +%u)  # 1=Mon
        DAYS_SINCE_MON=$((DOW - 1))
        MON_THIS=$(iwe_date_shift -${DAYS_SINCE_MON})
        TODAY=$(date +%Y-%m-%d)

        # Previous week
        MON_PREV=$(iwe_date_shift -$((DAYS_SINCE_MON + 7)))
        SUN_PREV=$(iwe_date_shift -$((DAYS_SINCE_MON + 1)))

        RESP_THIS=$(strategist_wakatime_fetch "$ENCODED" "$API/summaries?start=$MON_THIS&end=$TODAY")
        RESP_PREV=$(strategist_wakatime_fetch "$ENCODED" "$API/summaries?start=$MON_PREV&end=$SUN_PREV")

        TOTAL_THIS=$(strategist_wakatime_extract_total "$RESP_THIS")
        TOTAL_PREV=$(strategist_wakatime_extract_total "$RESP_PREV")
        PROJECTS_THIS=$(strategist_wakatime_aggregate_items "$RESP_THIS" projects)
        PROJECTS_PREV=$(strategist_wakatime_aggregate_items "$RESP_PREV" projects)
        LANGS_THIS=$(strategist_wakatime_aggregate_items "$RESP_THIS" languages)

        cat <<EOF
## WakaTime: статистика рабочего времени

### Текущая неделя ($MON_THIS — $TODAY)

**Общее время:** $TOTAL_THIS

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_THIS" | strategist_wakatime_format_projects)

**По языкам:**

| Язык | Время |
|------|-------|
$(echo "$LANGS_THIS" | strategist_wakatime_format_languages)

### Предыдущая неделя ($MON_PREV — $SUN_PREV)

**Общее время:** $TOTAL_PREV

**По проектам:**

| Проект | Время |
|--------|-------|
$(echo "$PROJECTS_PREV" | strategist_wakatime_format_projects)

**Сравнение:** текущая $TOTAL_THIS vs предыдущая $TOTAL_PREV
EOF
        ;;

    *)
        echo "Usage: $0 {day|week}"
        exit 1
        ;;
esac
