#!/bin/bash
# Шаблон уведомлений: Экстрактор (R2)
# Вызывается из notify.sh через source
# Требует: WORKSPACE_DIR (env или аргумент)

WORKSPACE_DIR="${WORKSPACE_DIR:-}"
if [ -z "$WORKSPACE_DIR" ]; then
  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --workspace-dir) WORKSPACE_DIR="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
  fi
fi
if [ -z "$WORKSPACE_DIR" ]; then
  echo "Ошибка: WORKSPACE_DIR не задан" >&2
  exit 1
fi

REPORTS_DIR="$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports"
DATE=$(date +%Y-%m-%d)

build_message() {
    local process="$1"

    case "$process" in
        "inbox-check")
            local report
            report=$(ls -t "$REPORTS_DIR"/${DATE}-*.md 2>/dev/null | head -1)

            if [ -z "$report" ] || [ ! -f "$report" ]; then
                echo ""
                return
            fi

            local candidates
            candidates=$(grep -c '^## Кандидат' "$report" 2>/dev/null || echo "0")
            local accept
            accept=$(grep -c 'Вердикт.*accept' "$report" 2>/dev/null || echo "0")

            printf "<b>🔍 Knowledge Extractor: %s</b>\n\n" "$process"
            printf "📅 %s\n\n" "$DATE"
            printf "📊 Кандидатов: %s, Accept: %s\n\n" "$candidates" "$accept"

            if [ "$candidates" -gt 0 ]; then
                printf "Для применения: в Claude скажите «review extraction report»"
            else
                printf "Inbox пуст."
            fi
            ;;

        "audit")
            printf "<b>🔍 Knowledge Audit завершён</b>\n\n📅 %s\n\nПроверьте лог: %s/logs/synchronizer/%s.log" "$DATE" "$WORKSPACE_DIR" "$DATE"
            ;;

        *)
            echo ""
            ;;
    esac
}

build_buttons() {
    echo '[]'
}
