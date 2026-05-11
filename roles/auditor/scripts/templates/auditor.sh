#!/bin/bash
# Шаблон уведомлений: Аудитор (R24)
# Вызывается из notify_telegram() через bash -c 'source ...'

WORKSPACE_DIR="${WORKSPACE_DIR:-}"

build_message() {
  local scenario="$1"

  case "$scenario" in
    "audit-plan-consistency")
      printf '<b>Аудит планов</b>\n\nПроверка согласованности планов завершена.'
      ;;
    "audit-coverage")
      printf '<b>Аудит покрытия</b>\n\nПроверка покрытия завершена.'
      ;;
    "on-demand")
      printf '<b>Аудит по запросу</b>\n\nOn-demand аудит завершён.'
      ;;
    *)
      echo ""
      ;;
  esac
}

build_buttons() {
  echo '[]'
}
