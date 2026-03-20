#!/usr/bin/env bash
# Library-Class: source-pure

if [[ -n "${_LIB_PLATFORM_LOADED:-}" ]]; then
  return 0
fi
readonly _LIB_PLATFORM_LOADED=1

function iwe_detect_os() {
  case "$(uname -s)" in
    Linux*)
      printf '%s\n' 'linux'
      ;;
    Darwin*)
      printf '%s\n' 'macos'
      ;;
    *)
      printf '%s\n' 'unknown'
      ;;
  esac
}

function iwe_sed_inplace() {
  if [[ "${1:-}" == "append" ]]; then
    printf '%s\n' "$3" >> "$2"
    return 0
  fi

  if [[ "$(iwe_detect_os)" == "macos" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

function iwe_date_shift() {
  local days="${1}"
  local fmt="${2:-%Y-%m-%d}"

  if [[ "$(iwe_detect_os)" == "macos" ]]; then
    if [[ "${days}" == -* ]]; then
      date -v"${days}"d +"${fmt}"
    else
      date -v+"${days}"d +"${fmt}"
    fi
  else
    date -d "${days} days" +"${fmt}"
  fi
}

function iwe_date_days_ago() {
  local days="${1}"
  local fmt="${2:-%Y-%m-%d}"
  iwe_date_shift "-${days}" "${fmt}"
}
