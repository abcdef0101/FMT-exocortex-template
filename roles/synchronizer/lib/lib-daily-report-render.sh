#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_DAILY_REPORT_LIB_RENDER_LOADED:-}" ]]; then
  return 0
fi
readonly _DAILY_REPORT_LIB_RENDER_LOADED=1

function daily_report_compute_traffic_light() {
  local state_dir="${1}"
  local scheduler_log="${2}"
  local dow_value="${3}"
  local hour_value="${4}"
  local date_value="${5}"
  local week_value="${6}"

  local color="GREEN"
  local issues=""

  if ! daily_report_check_ran "${state_dir}" "synchronizer-code-scan" "${date_value}" >/dev/null 2>&1; then
    color="RED"
    issues+="code-scan не запустился; "
  fi

  if (( 10#${hour_value} >= 6 )) && ! daily_report_check_ran "${state_dir}" "strategist-morning" "${date_value}" >/dev/null 2>&1; then
    color="RED"
    issues+="strategist morning не запустился; "
  fi

  if [[ -f "${scheduler_log}" ]] && grep -q "push failed" "${scheduler_log}" 2>/dev/null; then
    [[ "${color}" == "GREEN" ]] && color="YELLOW"
    issues+="push failed (Mac оффлайн?); "
  fi

  if (( 10#${hour_value} >= 23 )) && ! daily_report_check_ran "${state_dir}" "strategist-note-review" "${date_value}" >/dev/null 2>&1; then
    [[ "${color}" == "GREEN" ]] && color="YELLOW"
    issues+="note-review не запустился; "
  fi

  if [[ "${dow_value}" == "1" ]] && ! daily_report_check_ran_week "${state_dir}" "strategist-week-review" "${week_value}" >/dev/null 2>&1; then
    [[ "${color}" == "GREEN" ]] && color="YELLOW"
    issues+="week-review не запустился (Пн!); "
  fi

  local emoji label
  case "${color}" in
    GREEN)  emoji="🟢"; label="Среда готова к работе" ;;
    YELLOW) emoji="🟡"; label="Среда работает с замечаниями" ;;
    RED)    emoji="🔴"; label="Критический сбой — требуется внимание" ;;
  esac

  printf '%s|%s|%s\n' "${emoji}" "${label}" "${issues:-нет}"
}

function daily_report_generate() {
  local state_dir="${1}"
  local scheduler_log="${2}"
  local date_value="${3}"
  local dow_value="${4}"
  local hour_value="${5}"
  local week_value="${6}"
  local now_epoch="${7}"
  local workspace_dir="${8}"
  local report tl_result tl_emoji tl_label tl_issues warnings value

  report="---
type: scheduler-report
date: ${date_value}
week: W${week_value}
agent: Синхронизатор
---

# Отчёт планировщика: ${date_value}

"

  tl_result=$(daily_report_compute_traffic_light "${state_dir}" "${scheduler_log}" "${dow_value}" "${hour_value}" "${date_value}" "${week_value}")
  tl_emoji=$(echo "${tl_result}" | cut -d'|' -f1)
  tl_label=$(echo "${tl_result}" | cut -d'|' -f2)
  tl_issues=$(echo "${tl_result}" | cut -d'|' -f3)

  report+="## ${tl_emoji} ${tl_label}

"
  if [[ "${tl_issues}" != "нет" ]]; then
    report+="> **Замечания:** ${tl_issues}

"
  fi

  report+="## Результаты

| # | Задача | Статус | Время |
|---|--------|--------|-------|"

  if value=$(daily_report_check_ran "${state_dir}" "synchronizer-code-scan" "${date_value}"); then
    report+="
| 1 | Сканирование кода | **✅** | ${value} |"
  else
    report+="
| 1 | Сканирование кода | **❌** | — |"
  fi

  if value=$(daily_report_check_ran "${state_dir}" "strategist-morning" "${date_value}"); then
    report+="
| 2 | Стратег утренний | **✅** | ${value} |"
  else
    report+="
| 2 | Стратег утренний | **❌** | — |"
  fi

  if (( 10#${hour_value} >= 22 )); then
    if value=$(daily_report_check_ran "${state_dir}" "strategist-note-review" "${date_value}"); then
      report+="
| 3 | Разбор заметок | **✅** | ${value} |"
    else
      report+="
| 3 | Разбор заметок | **❌** | — |"
    fi
  fi

  if [[ "${dow_value}" == "1" ]]; then
    if value=$(daily_report_check_ran_week "${state_dir}" "strategist-week-review" "${week_value}"); then
      report+="
| 4 | Обзор недели | **✅** | ${value} |"
    else
      report+="
| 4 | Обзор недели | **❌** | — |"
    fi
  fi

  if value=$(daily_report_check_interval "${state_dir}" "extractor-inbox-check" "${now_epoch}"); then
    report+="
| 5 | Проверка входящих | **✅** | ${value} |"
  else
    report+="
| 5 | Проверка входящих | **❌** | — |"
  fi

  report+="

## Ошибки и предупреждения
"

  warnings=""
  if [[ -f "${scheduler_log}" ]]; then
    warnings=$(grep -E "WARN:|ERROR:|failed" "${scheduler_log}" 2>/dev/null | sed 's/^/- /' || true)
  fi

  if [[ -n "${warnings}" ]]; then
    report+="
${warnings}

**Что делать:**
"
    if echo "${warnings}" | grep -q "push failed" 2>/dev/null; then
      report+="- **push failed:** Mac был оффлайн. Запусти \`cd ${workspace_dir}/DS-strategy && git pull --rebase && git push\`
"
    fi
  else
    report+="
Нет ошибок. ✅
"
  fi

  printf '%s\n' "${report}"
}
