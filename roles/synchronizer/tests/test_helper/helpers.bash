# Общие хелперы для тестов synchronizer

# Вычислить путь к ENV_FILE так же как делает скрипт:
#   _iwe_ws = scripts/../../../../  (4 уровня вверх от scripts/)
#   ENV_FILE = $HOME/.<basename _iwe_ws>/env
make_iwe_env() {
    local script_dir="${1}"       # путь к scripts/ директории
    local home_dir="${2}"         # тестовый $HOME
    local workspace="${3}"        # WORKSPACE_DIR
    local extras="${4:-}"         # дополнительные переменные

    local iwe_ws
    iwe_ws="$(cd "$script_dir/../../../.." && pwd)"
    local env_dir="$home_dir/.$(basename "$iwe_ws")"
    mkdir -p "$env_dir"
    cat > "$env_dir/env" <<EOF
WORKSPACE_DIR=$workspace
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
EXOCORTEX_REPO=DS-exocortex
$extras
EOF
    echo "$env_dir/env"
}

# Создать мок-git в PATH: возвращает заданные коммиты для log
make_git_mock() {
    local bin_dir="$1"
    local commits="${2:-}"   # список коммитов (пустой = нет коммитов)
    mkdir -p "$bin_dir"
    cat > "$bin_dir/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"log"* ]]; then
    printf '%s\n' $commits
else
    /usr/bin/git "\$@"
fi
EOF
    chmod +x "$bin_dir/git"
    export PATH="$bin_dir:$PATH"
}

# Создать мок-curl: возвращает JSON-ответ Telegram
make_curl_mock() {
    local bin_dir="$1"
    local response="${2:-{\"ok\":true}}"
    local exit_code="${3:-0}"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/curl" <<EOF
#!/usr/bin/env bash
echo '$response'
exit $exit_code
EOF
    chmod +x "$bin_dir/curl"
    export PATH="$bin_dir:$PATH"
}

# Загрузить функции scheduler без выполнения main-логики
load_scheduler_fns() {
    local state_dir="$1"
    local log_dir="$2"
    local date="${3:-$(date +%Y-%m-%d)}"
    local week="${4:-$(date +%V)}"
    local now="${5:-$(date +%s)}"

    source /dev/stdin <<EOF
STATE_DIR="$state_dir"
LOG_DIR="$log_dir"
DATE="$date"
WEEK="$week"
NOW="$now"
mkdir -p "\$STATE_DIR" "\$LOG_DIR"

portable_date_offset() {
    local days="\$1"
    local fmt="\${2:-%Y-%m-%d}"
    date -v-\${days}d +"\$fmt" 2>/dev/null || date -d "\$days days ago" +"\$fmt" 2>/dev/null
}

ran_today() {
    [ -f "\$STATE_DIR/\$1-\$DATE" ]
}

ran_this_week() {
    [ -f "\$STATE_DIR/\$1-W\$WEEK" ]
}

mark_done() {
    echo "\$(date '+%H:%M:%S')" > "\$STATE_DIR/\$1-\$DATE"
}

mark_done_week() {
    echo "\$DATE \$(date '+%H:%M:%S')" > "\$STATE_DIR/\$1-W\$WEEK"
}

last_run_seconds_ago() {
    local marker="\$STATE_DIR/\$1-last"
    if [ -f "\$marker" ]; then
        local prev
        prev=\$(cat "\$marker")
        echo \$(( NOW - prev ))
    else
        echo 999999
    fi
}

mark_interval() {
    echo "\$NOW" > "\$STATE_DIR/\$1-last"
}

cleanup_state() {
    find "\$STATE_DIR" -name "*-202*" -mtime +7 -delete 2>/dev/null || true
}

log() {
    local LOG_FILE="\$LOG_DIR/scheduler-\$DATE.log"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [scheduler] \$1" | tee -a "\$LOG_FILE"
}
EOF
}

# Загрузить функции daily-report без main
load_daily_report_fns() {
    local state_dir="$1"
    local log_dir="$2"
    local date="${3:-$(date +%Y-%m-%d)}"
    local week="${4:-$(date +%V)}"
    local dow="${5:-$(date +%u)}"
    local hour="${6:-10}"

    source /dev/stdin <<EOF
STATE_DIR="$state_dir"
LOG_DIR="$log_dir"
DATE="$date"
WEEK="$week"
DOW="$dow"
HOUR="$hour"
SCHEDULER_LOG="$log_dir/scheduler-$date.log"
mkdir -p "\$STATE_DIR" "\$LOG_DIR"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [daily-report] \$1"; }

check_ran() {
    local marker="\$1"
    if [ -f "\$STATE_DIR/\$marker-\$DATE" ]; then
        cat "\$STATE_DIR/\$marker-\$DATE"
        return 0
    fi
    return 1
}

check_ran_week() {
    local marker="\$1"
    if [ -f "\$STATE_DIR/\$marker-W\$WEEK" ]; then
        cat "\$STATE_DIR/\$marker-W\$WEEK"
        return 0
    fi
    return 1
}

check_interval() {
    local marker="\$1-last"
    if [ -f "\$STATE_DIR/\$marker" ]; then
        local ts ago
        ts=\$(cat "\$STATE_DIR/\$marker")
        ago=\$(( \$(date +%s) - ts ))
        echo "\${ago} сек назад"
        return 0
    fi
    return 1
}

compute_traffic_light() {
    local color="GREEN"
    local issues=""

    if ! check_ran "synchronizer-code-scan" &>/dev/null; then
        color="RED"
        issues+="code-scan не запустился; "
    fi

    if (( 10#\$HOUR >= 6 )) && ! check_ran "strategist-morning" &>/dev/null; then
        color="RED"
        issues+="strategist morning не запустился; "
    fi

    if [ -f "\$SCHEDULER_LOG" ] && grep -q "push failed" "\$SCHEDULER_LOG" 2>/dev/null; then
        if [ "\$color" = "GREEN" ]; then color="YELLOW"; fi
        issues+="push failed (Mac оффлайн?); "
    fi

    if (( 10#\$HOUR >= 23 )) && ! check_ran "strategist-note-review" &>/dev/null; then
        if [ "\$color" = "GREEN" ]; then color="YELLOW"; fi
        issues+="note-review не запустился; "
    fi

    if [ "\$DOW" = "1" ] && ! check_ran_week "strategist-week-review" &>/dev/null; then
        if [ "\$color" = "GREEN" ]; then color="YELLOW"; fi
        issues+="week-review не запустился (Пн!); "
    fi

    local emoji label
    case "\$color" in
        GREEN)  emoji="🟢"; label="Среда готова к работе" ;;
        YELLOW) emoji="🟡"; label="Среда работает с замечаниями" ;;
        RED)    emoji="🔴"; label="Критический сбой — требуется внимание" ;;
    esac

    echo "\$emoji|\$label|\${issues:-нет}"
}
EOF
}
