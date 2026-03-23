#!/usr/bin/env bash
# scheduler.sh — центральный диспетчер агентов экзокортекса
# Targets: Linux, macOS
#
# Вызывается launchd (com.exocortex.scheduler) в нужные моменты.
# Состояние: ~/.local/state/exocortex/ (маркеры запуска)
#
# Использование:
#   scheduler.sh dispatch    — проверить расписание и запустить что нужно
#   scheduler.sh status      — показать состояние всех агентов

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=lib/lib-platform.sh
source "${SCRIPT_DIR}/../../../lib/lib-platform.sh"

# shellcheck source=roles/synchronizer/lib/lib-scheduler-state.sh
source "${SCRIPT_DIR}/../lib/lib-scheduler-state.sh"

# shellcheck source=roles/synchronizer/lib/lib-scheduler-dispatch.sh
source "${SCRIPT_DIR}/../lib/lib-scheduler-dispatch.sh"

REPO_ROOT="$(iwe_find_repo_root "${SCRIPT_DIR}")" || {
    echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2
    exit 1
}
ENV_FILE="$(iwe_env_file_from_repo_root "${REPO_ROOT}")"

iwe_load_env_file "${ENV_FILE}" || exit 1
iwe_require_env_vars WORKSPACE_DIR || exit 1

SYNC_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$HOME/.local/state/exocortex"
LOG_DIR="$HOME/.local/state/logs/synchronizer"
LOG_FILE="$LOG_DIR/scheduler-$(date +%Y-%m-%d).log"

ROLES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NOTIFY_SH="$REPO_ROOT/scripts/notify.sh"

STRATEGIST_SH="$(scheduler_get_role_runner "$ROLES_DIR" strategist)"
EXTRACTOR_SH="$(scheduler_get_role_runner "$ROLES_DIR" extractor)"

# Текущее время
HOUR=$(date +%H)
DOW=$(date +%u)   # 1=Mon, 7=Sun
DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
NOW=$(date +%s)

mkdir -p "$STATE_DIR" "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [scheduler] $1" | tee -a "$LOG_FILE"
}

# === Управление состоянием ===

ran_today() {
    [ -f "$STATE_DIR/$1-$DATE" ]
}

ran_this_week() {
    [ -f "$STATE_DIR/$1-W$WEEK" ]
}

mark_done() {
    echo "$(date '+%H:%M:%S')" > "$STATE_DIR/$1-$DATE"
}

mark_done_week() {
    echo "$DATE $(date '+%H:%M:%S')" > "$STATE_DIR/$1-W$WEEK"
}

last_run_seconds_ago() {
    local marker="$STATE_DIR/$1-last"
    if [ -f "$marker" ]; then
        local prev
        prev=$(cat "$marker")
        echo $(( NOW - prev ))
    else
        echo 999999
    fi
}

mark_interval() {
    echo "$NOW" > "$STATE_DIR/$1-last"
}

# === Очистка старых маркеров (>7 дней) ===

cleanup_state() {
    find "$STATE_DIR" -name "*-202*" -mtime +7 -delete 2>/dev/null || true
}

# === Pre-archive: мгновенная очистка вчерашнего DayPlan (< 1 сек) ===
# Разделяет архивацию (мгновенно) и генерацию (15+ мин Claude Code).
# Гарантирует: даже если генерация ещё не началась, старый план не висит в current/.
pre_archive_dayplan() {
    local strategy_dir="{{WORKSPACE_DIR}}/DS-strategy"
    local archive_dir="$strategy_dir/archive/day-plans"
    local moved=0

    mkdir -p "$archive_dir"

    for dayplan in "$strategy_dir/current"/DayPlan\ 20*.md; do
        [ -f "$dayplan" ] || continue
        local fname
        fname=$(basename "$dayplan")
        # Пропускаем сегодняшний план
        if [[ "$fname" == *"$DATE"* ]]; then continue; fi
        # Архивируем вчерашний (и любой более старый)
        git -C "$strategy_dir" mv "$dayplan" "$archive_dir/" 2>/dev/null || mv "$dayplan" "$archive_dir/"
        moved=$((moved + 1))
        log "pre-archive: moved $fname → archive/day-plans/"
    done

    if [ "$moved" -gt 0 ]; then
        git -C "$strategy_dir" pull --rebase 2>/dev/null || true
        # ВАЖНО: добавляем ТОЛЬКО перемещённые файлы, не всю директорию.
        # `git add current/` может подхватить грязные unstaged файлы (баг 21 мар 2026).
        git -C "$strategy_dir" add -- archive/day-plans/ 2>/dev/null || true
        git -C "$strategy_dir" add -u -- current/ 2>/dev/null || true
        git -C "$strategy_dir" commit -m "chore: archive $moved old DayPlan(s)" 2>/dev/null || true
        git -C "$strategy_dir" push 2>/dev/null || true
        log "pre-archive: committed and pushed ($moved file(s))"
    fi
}

# === Диспетчер ===

dispatch() {
    log "dispatch started (hour=$HOUR, dow=$DOW)"
    local ran=0

    # --- Pre-archive: убрать вчерашний DayPlan ДО генерации нового ---
    scheduler_pre_archive_dayplan "$WORKSPACE_DIR" "$DATE" log

    # --- Стратег: week-review (Пн, до morning) ---
    if [ "$DOW" = "1" ] && ! scheduler_ran_this_week "$STATE_DIR" "strategist-week-review" "$WEEK"; then
        log "→ strategist week-review (catch-up: hour=$HOUR)"
        scheduler_run_and_mark_weekly "$STRATEGIST_SH" "week-review" "$STATE_DIR" "strategist-week-review" "$DATE" "$WEEK" "$LOG_FILE" log "WARN: strategist week-review failed (will retry next dispatch)" || true
        ran=1
    fi

    # --- Стратег: morning (04:00-21:59) ---
    if (( 10#$HOUR >= 4 && 10#$HOUR < 22 )) && ! scheduler_ran_today "$STATE_DIR" "strategist-morning" "$DATE"; then
        log "→ strategist morning (catch-up: hour=$HOUR)"
        scheduler_run_and_mark_daily "$STRATEGIST_SH" "morning" "$STATE_DIR" "strategist-morning" "$DATE" "$LOG_FILE" log "WARN: strategist morning failed (will retry next dispatch)" || true
        ran=1
    fi

    # --- Стратег: note-review (22:00+) ---
    if (( 10#$HOUR >= 22 )) && ! scheduler_ran_today "$STATE_DIR" "strategist-note-review" "$DATE"; then
        log "→ strategist note-review (catch-up: hour=$HOUR)"
        if "$STRATEGIST_SH" note-review >> "$LOG_FILE" 2>&1; then
            scheduler_mark_done "$STATE_DIR" "strategist-note-review" "$DATE"
        else
            log "WARN: strategist note-review failed (will retry next dispatch)"
        fi
        ran=1
    elif (( 10#$HOUR < 12 )); then
        local yesterday
        yesterday=$(iwe_date_days_ago 1)
        if [ -n "$yesterday" ] && [ ! -f "$STATE_DIR/strategist-note-review-$yesterday" ]; then
            log "→ strategist note-review (catch-up for yesterday $yesterday)"
            if "$STRATEGIST_SH" note-review >> "$LOG_FILE" 2>&1; then
                echo "$(date '+%H:%M:%S') catch-up" > "$STATE_DIR/strategist-note-review-$yesterday"
            else
                log "WARN: strategist note-review catch-up failed"
            fi
            ran=1
        fi
    fi

    # --- Синхронизатор: code-scan (ежедневно) ---
    if ! scheduler_ran_today "$STATE_DIR" "synchronizer-code-scan" "$DATE"; then
        log "→ synchronizer code-scan (hour=$HOUR)"
        if "$SCRIPT_DIR/code-scan.sh" >> "$LOG_FILE" 2>&1; then
            scheduler_mark_done "$STATE_DIR" "synchronizer-code-scan" "$DATE"
        else
            log "WARN: code-scan failed (will retry next dispatch)"
        fi
        ran=1
    fi

    # --- Синхронизатор: dt-collect (после code-scan) ---
    if ! scheduler_ran_today "$STATE_DIR" "synchronizer-dt-collect" "$DATE"; then
        log "→ synchronizer dt-collect (hour=$HOUR)"
        if "$SCRIPT_DIR/dt-collect.sh" >> "$LOG_FILE" 2>&1; then
            scheduler_mark_done "$STATE_DIR" "synchronizer-dt-collect" "$DATE"
        else
            log "WARN: dt-collect failed (will retry next dispatch)"
        fi
        ran=1
    fi

    # --- Синхронизатор: daily-report (после code-scan и strategist morning) ---
    if ! scheduler_ran_today "$STATE_DIR" "synchronizer-daily-report" "$DATE"; then
        if scheduler_ran_today "$STATE_DIR" "strategist-morning" "$DATE" || (( 10#$HOUR >= 6 )); then
            log "→ synchronizer daily-report (hour=$HOUR)"
            if "$SCRIPT_DIR/daily-report.sh" >> "$LOG_FILE" 2>&1; then
                scheduler_mark_done "$STATE_DIR" "synchronizer-daily-report" "$DATE"
            else
                log "WARN: daily-report failed (will retry next dispatch)"
            fi
            ran=1
        fi
    fi

    # --- Экстрактор: inbox-check (каждые 3ч, 07-23) ---
    if (( 10#$HOUR >= 7 && 10#$HOUR <= 23 )); then
        local elapsed
        elapsed=$(scheduler_last_run_seconds_ago "$STATE_DIR" "extractor-inbox-check" "$NOW")
        if [ "$elapsed" -ge 10800 ]; then
            log "→ extractor inbox-check (${elapsed}s since last)"
            if "$EXTRACTOR_SH" inbox-check >> "$LOG_FILE" 2>&1; then
                scheduler_mark_interval "$STATE_DIR" "extractor-inbox-check" "$NOW"
            else
                log "WARN: extractor inbox-check failed (will retry next dispatch)"
            fi
            ran=1
        fi
    fi

    if [ "$ran" -eq 0 ]; then
        log "dispatch: nothing to run"
    fi

    scheduler_cleanup_state "$STATE_DIR"
    log "dispatch completed"
}

# === Статус ===

show_status() {
    scheduler_show_status "$STATE_DIR" "$DATE" "$HOUR" "$DOW" "$WEEK" "$NOW"
}

# === Main ===

case "${1:-}" in
    dispatch)
        dispatch
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: scheduler.sh {dispatch|status}"
        echo ""
        echo "  dispatch  — check schedules and run due agents"
        echo "  status    — show current state of all agents"
        exit 1
        ;;
esac
