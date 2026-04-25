#!/bin/bash
# Шаблон уведомлений: Синхронизатор (R8)
# Вызывается из notify.sh через source
# Требует: WORKSPACE_DIR (env или аргумент)

WORKSPACE_DIR="${WORKSPACE_DIR:-}"
if [ -z "$WORKSPACE_DIR" ]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace-dir) WORKSPACE_DIR="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
fi
if [ -z "$WORKSPACE_DIR" ]; then
  echo "Ошибка: WORKSPACE_DIR не задан" >&2
  exit 1
fi

LOG_DIR="$WORKSPACE_DIR/logs/synchronizer"
DATE=$(date +%Y-%m-%d)

build_message() {
    local scenario="$1"

    case "$scenario" in
        "code-scan")
            local log_file="$LOG_DIR/code-scan-$DATE.log"

            if [ ! -f "$log_file" ]; then
                echo ""
                return
            fi

            local latest_run
            latest_run=$(awk '/=== Code Scan Started ===/{buf=""} {buf=buf"\n"$0} END{print buf}' "$log_file" 2>/dev/null)

            local found
            found=$(echo "$latest_run" | grep -c 'FOUND:' 2>/dev/null || echo "0")
            local skipped
            skipped=$(echo "$latest_run" | grep -c 'SKIP:' 2>/dev/null || echo "0")

            local repo_list
            repo_list=$(echo "$latest_run" | grep 'FOUND:' 2>/dev/null | sed 's/.*FOUND: /  /' || echo "")

            printf "<b>🔄 Code Scan</b>\n\n"
            printf "📅 %s\n\n" "$DATE"
            printf "Репо с коммитами: %s\n" "$found"
            printf "Без изменений: %s\n\n" "$skipped"

            if [ "$found" -gt 0 ]; then
                printf "<b>Репо:</b>\n%s" "$repo_list"
            fi
            ;;

        "dt-collect")
            local log_file="$LOG_DIR/dt-collect-$DATE.log"

            if [ ! -f "$log_file" ]; then
                echo ""
                return
            fi

            local status_line
            status_line=$(grep -E '=== DT Collect (Completed|Started)' "$log_file" | tail -1)

            if echo "$status_line" | grep -q 'Completed Successfully'; then
                printf "<b>📊 DT Collect</b>\n\n📅 %s\n\nЦД обновлён." "$DATE"
            else
                printf "<b>📊 DT Collect</b>\n\n📅 %s\n\n⚠️ Проверьте лог." "$DATE"
            fi
            ;;

        *)
            echo ""
            ;;
    esac
}

build_buttons() {
    echo '[]'
}
