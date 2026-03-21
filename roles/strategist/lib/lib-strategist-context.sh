#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_STRATEGIST_LIB_CONTEXT_LOADED:-}" ]]; then
  return 0
fi
readonly _STRATEGIST_LIB_CONTEXT_LOADED=1

function strategist_python_required() {
  command -v python3 >/dev/null 2>&1
}

function strategist_read_strategy_day_name() {
  local rhythm_config="${1}"
  grep 'strategy_day:' "${rhythm_config}" 2>/dev/null | awk '{print $2}' || echo "monday"
}

function strategist_day_name_to_num() {
  case "${1}" in
    monday)    printf '%s\n' '1' ;;
    tuesday)   printf '%s\n' '2' ;;
    wednesday) printf '%s\n' '3' ;;
    thursday)  printf '%s\n' '4' ;;
    friday)    printf '%s\n' '5' ;;
    saturday)  printf '%s\n' '6' ;;
    sunday)    printf '%s\n' '7' ;;
    *)         printf '%s\n' '1' ;;
  esac
}

function strategist_build_ru_date_context() {
  local iso_date="${1}"
  python3 -c "
import datetime
days = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье']
months = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря']
d = datetime.date.fromisoformat('${iso_date}')
print(f'{d.day} {months[d.month-1]} {d.year}, {days[d.weekday()]}')
"
}

function strategist_resolve_morning_scenario() {
  local day_of_week="${1}"
  local strategy_day_num="${2}"

  if [[ "${day_of_week}" -eq "${strategy_day_num}" ]]; then
    printf '%s\n' 'session-prep'
  else
    printf '%s\n' 'day-plan'
  fi
}
