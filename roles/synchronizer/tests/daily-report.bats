#!/usr/bin/env bats
# Тесты для roles/synchronizer/scripts/daily-report.sh
# Покрывает: check_ran, check_ran_week, check_interval,
#            compute_traffic_light, archive_old_reports

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'
load 'test_helper/helpers'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    STATE_DIR="$TEST_DIR/state"
    LOG_DIR="$TEST_DIR/logs"
    DATE=$(date +%Y-%m-%d)
    WEEK=$(date +%V)
    DOW=$(date +%u)
    mkdir -p "$STATE_DIR" "$LOG_DIR"
}

# ---------------------------------------------------------------------------
# check_ran
# ---------------------------------------------------------------------------

@test "check_ran: failure если маркер не существует" {
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_ran "strategist-morning"
    assert_failure
}

@test "check_ran: success если маркер существует" {
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_ran "strategist-morning"
    assert_success
    assert_output "07:00:00"
}

@test "check_ran: разные маркеры изолированы" {
    echo "10:00:00" > "$STATE_DIR/task-a-$DATE"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_ran "task-b"
    assert_failure
}

# ---------------------------------------------------------------------------
# check_ran_week
# ---------------------------------------------------------------------------

@test "check_ran_week: failure если маркер не существует" {
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_ran_week "strategist-week-review"
    assert_failure
}

@test "check_ran_week: success если маркер существует" {
    echo "$DATE 09:00:00" > "$STATE_DIR/strategist-week-review-W$WEEK"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_ran_week "strategist-week-review"
    assert_success
    assert_output --partial "$DATE"
}

# ---------------------------------------------------------------------------
# check_interval
# ---------------------------------------------------------------------------

@test "check_interval: failure если маркер не существует" {
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_interval "dt-collect"
    assert_failure
}

@test "check_interval: success если маркер существует" {
    echo "$(date +%s)" > "$STATE_DIR/dt-collect-last"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "$DOW" "10"
    run check_interval "dt-collect"
    assert_success
    assert_output --partial "сек назад"
}

# ---------------------------------------------------------------------------
# compute_traffic_light
# ---------------------------------------------------------------------------

@test "compute_traffic_light: GREEN если всё запустилось" {
    # Создаём все нужные маркеры
    echo "06:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "2" "10"  # Вт, 10ч

    run compute_traffic_light
    assert_success
    assert_output --partial "🟢"
    assert_output --partial "готова к работе"
}

@test "compute_traffic_light: RED если code-scan не запустился" {
    # НЕ создаём маркер code-scan
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "2" "10"

    run compute_traffic_light
    assert_success
    assert_output --partial "🔴"
    assert_output --partial "code-scan не запустился"
}

@test "compute_traffic_light: RED если morning не запустился после 6ч" {
    echo "06:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    # НЕ создаём маркер morning
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "2" "10"

    run compute_traffic_light
    assert_success
    assert_output --partial "🔴"
    assert_output --partial "strategist morning не запустился"
}

@test "compute_traffic_light: GREEN если morning не запустился до 6ч" {
    echo "05:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    echo "05:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    # HOUR=5 — до 6 утра, morning ещё не должен был запуститься
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "2" "5"

    run compute_traffic_light
    assert_success
    assert_output --partial "🟢"
}

@test "compute_traffic_light: YELLOW если push failed в логе" {
    echo "06:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    # Логируем push failed
    echo "push failed: network error" > "$LOG_DIR/scheduler-$DATE.log"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "2" "10"

    run compute_traffic_light
    assert_success
    assert_output --partial "🟡"
    assert_output --partial "push failed"
}

@test "compute_traffic_light: YELLOW в понедельник без week-review" {
    echo "06:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    # DOW=1 (Пн), нет week-review маркера
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "1" "10"

    run compute_traffic_light
    assert_success
    assert_output --partial "🟡"
    assert_output --partial "week-review"
}

@test "compute_traffic_light: GREEN в понедельник с week-review" {
    echo "06:00:00" > "$STATE_DIR/synchronizer-code-scan-$DATE"
    echo "07:00:00" > "$STATE_DIR/strategist-morning-$DATE"
    echo "$DATE 09:00:00" > "$STATE_DIR/strategist-week-review-W$WEEK"
    load_daily_report_fns "$STATE_DIR" "$LOG_DIR" "$DATE" "$WEEK" "1" "10"

    run compute_traffic_light
    assert_success
    assert_output --partial "🟢"
}

# ---------------------------------------------------------------------------
# archive_old_reports (inline)
# ---------------------------------------------------------------------------

_load_archive_reports() {
    local report_dir="$1"
    local archive_dir="$2"
    source /dev/stdin <<EOF
archive_old_reports() {
    local report_dir="$report_dir"
    local archive_dir="$archive_dir"
    mkdir -p "\$archive_dir"
    local count=0
    for f in "\$report_dir"/SchedulerReport\ *.md; do
        [ -f "\$f" ] || continue
        local fname=\$(basename "\$f")
        local report_date
        report_date=\$(echo "\$fname" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        [ -z "\$report_date" ] && continue
        [ "\$report_date" = "\$(date +%Y-%m-%d)" ] && continue
        mv "\$f" "\$archive_dir/\$fname"
        count=\$((count + 1))
    done
    echo "Archived: \$count report(s)"
}
EOF
}

@test "archive_old_reports: перемещает вчерашний отчёт в архив" {
    local report_dir="$TEST_DIR/reports"
    local archive_dir="$TEST_DIR/archive"
    mkdir -p "$report_dir" "$archive_dir"
    local yesterday
    yesterday=$(date -d "1 days ago" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
    echo "# Report" > "$report_dir/SchedulerReport $yesterday.md"

    _load_archive_reports "$report_dir" "$archive_dir"
    run archive_old_reports
    assert_success
    assert_output --partial "Archived: 1"
    assert_file_exist "$archive_dir/SchedulerReport $yesterday.md"
}

@test "archive_old_reports: не трогает сегодняшний отчёт" {
    local report_dir="$TEST_DIR/reports2"
    local archive_dir="$TEST_DIR/archive2"
    mkdir -p "$report_dir" "$archive_dir"
    local today
    today=$(date +%Y-%m-%d)
    echo "# Today Report" > "$report_dir/SchedulerReport $today.md"

    _load_archive_reports "$report_dir" "$archive_dir"
    run archive_old_reports
    assert_success
    assert_output --partial "Archived: 0"
    assert_file_exist "$report_dir/SchedulerReport $today.md"
}

@test "archive_old_reports: нет отчётов — Archived: 0" {
    local report_dir="$TEST_DIR/reports3"
    local archive_dir="$TEST_DIR/archive3"
    mkdir -p "$report_dir" "$archive_dir"

    _load_archive_reports "$report_dir" "$archive_dir"
    run archive_old_reports
    assert_success
    assert_output --partial "Archived: 0"
}
