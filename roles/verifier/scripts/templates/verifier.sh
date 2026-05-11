#!/bin/bash
# Шаблон уведомлений: Верификатор (R23)
# Вызывается из notify_telegram() через bash -c 'source ...'

WORKSPACE_DIR="${WORKSPACE_DIR:-}"

build_message() {
  local scenario="$1"

  case "$scenario" in
    "verify-pack-entity")
      printf '<b>Верификация Pack Entity</b>\n\nПроверка сущностей Pack завершена.'
      ;;
    "verify-content")
      printf '<b>Верификация контента</b>\n\nПроверка контента завершена.'
      ;;
    "verify-wp-acceptance")
      printf '<b>Верификация приёмки РП</b>\n\nПроверка acceptance criteria завершена.'
      ;;
    "on-demand")
      printf '<b>Верификация по запросу</b>\n\nOn-demand верификация завершена.'
      ;;
    *)
      echo ""
      ;;
  esac
}

build_buttons() {
  echo '[]'
}
