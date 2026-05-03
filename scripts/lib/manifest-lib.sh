#!/usr/bin/env bash
# manifest-lib.sh — Парсинг и применение seed/manifest.yaml
# Используется setup.sh и update.sh для единого контракта установки/обновления
# ADR-005 §1

# === Cross-platform sed ===
if sed --version >/dev/null 2>&1; then
  sed_inplace() { sed -i "$@"; }
else
  sed_inplace() { sed -i '' "$@"; }
fi

# =========================================================================
# parse_manifest — читает manifest.yaml и выполняет callback для каждого артефакта
# Usage: parse_manifest <manifest_path> <callback_function>
# Callback получает позиционные аргументы:
#   $1=source $2=target $3=strategy $4=symlink_target $5=placeholders
# =========================================================================
parse_manifest() {
  local manifest_file="$1"
  local callback="$2"

  if [ ! -f "$manifest_file" ]; then
    echo "  ERROR: manifest file not found: $manifest_file" >&2
    return 1
  fi

  local in_artifacts=false in_entry=false
  local src="" tgt="" st="" sym="" phs=""

  # Функция сброса текущего артефакта
  _flush() {
    if $in_entry && [ -n "$tgt" ] && [ -n "$st" ]; then
      "$callback" "$src" "$tgt" "$st" "$sym" "$phs"
    fi
    in_entry=false
    src=""
    tgt=""
    st=""
    sym=""
    phs=""
  }

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Section tracking: enter/exit artifacts section
    if [[ "$line" =~ ^artifacts: ]]; then
      in_artifacts=true
      continue
    fi
    if $in_artifacts && [[ "$line" =~ ^never_touch: ]]; then
      _flush
      in_artifacts=false
      continue
    fi
    $in_artifacts || continue

    # New artifact entry: line starting with "  - source:" or "  - target:"
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(source|target):[[:space:]]*(.*) ]]; then
      _flush
      in_entry=true
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      # Trim trailing whitespace
      val="${val%"${val##*[![:space:]]}"}"
      case "$key" in
        source) src="$val" ;;
        target) tgt="$val" ;;
      esac
      continue
    fi

    $in_entry || continue

    # Parse fields within an artifact entry
    if [[ "$line" =~ ^[[:space:]]*target:[[:space:]]*(.*) ]]; then
      tgt="${BASH_REMATCH[1]}"
      tgt="${tgt%"${tgt##*[![:space:]]}"}"
    elif [[ "$line" =~ ^[[:space:]]*strategy:[[:space:]]*(.*) ]]; then
      st="${BASH_REMATCH[1]}"
      st="${st%"${st##*[![:space:]]}"}"
    elif [[ "$line" =~ ^[[:space:]]*symlink_target:[[:space:]]*(.*) ]]; then
      sym="${BASH_REMATCH[1]}"
      sym="${sym%"${sym##*[![:space:]]}"}"
    elif [[ "$line" =~ ^[[:space:]]*placeholders: ]]; then
      phs=""
    elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"(.+)\" ]]; then
      phs="$phs ${BASH_REMATCH[1]}"
    fi
    # description: and section: fields are ignored (documentation only)
  done < "$manifest_file"

  _flush  # последний артефакт
}

# =========================================================================
# apply_strategy — выполняет копирование/линковку согласно стратегии
# =========================================================================
apply_strategy() {
  local source="$1"
  local target="$2"
  local strategy="$3"
  local symlink_target="$4"
  local placeholders="$5"
  local dry_run="${6:-false}"

  case "$strategy" in
  copy-once)
    if [ -e "$target" ]; then
      echo "  skip (exists): $target"
      return 0
    fi
    if $dry_run; then
      echo "  [DRY RUN] copy-once: $source → $target"
    else
      local tdir; tdir="$(dirname "$target")"
      mkdir -p "$tdir"
      cp "$source" "$target" && echo "  copy-once: $target"
    fi
    ;;

  copy-if-newer)
    if $dry_run; then
      echo "  [DRY RUN] copy-if-newer: $source → $target"
    else
      local tdir; tdir="$(dirname "$target")"
      mkdir -p "$tdir"
      if [ -e "$target" ] && [ "$source" -ot "$target" ]; then
        echo "  skip (newer): $target"
        return 0
      fi
      cp "$source" "$target" && echo "  copy-if-newer: $target"
    fi
    ;;

  copy-and-substitute)
    if $dry_run; then
      echo "  [DRY RUN] copy-and-substitute: $source → $target"
      [ -n "$placeholders" ] && echo "    placeholders:$placeholders"
    else
      local tdir; tdir="$(dirname "$target")"
      mkdir -p "$tdir"
      cp "$source" "$target"
      if [ -n "$placeholders" ]; then
        for ph in $placeholders; do
          ph="${ph//\"/}"  # strip quotes
          local var_name="${ph//\{\{/}"
          var_name="${var_name//\}\}/}"
          local val="${!var_name:-$ph}"
          sed_inplace "s|$ph|$val|g" "$target" 2>/dev/null || true
          echo "    substituted: $ph → $val"
        done
      fi
      echo "  copy-and-substitute: $target"
    fi
    ;;

  symlink)
    if $dry_run; then
      echo "  [DRY RUN] symlink: $target → $symlink_target"
    else
      local tdir; tdir="$(dirname "$target")"
      mkdir -p "$tdir"
      if [ -L "$target" ]; then
        echo "  symlink exists: $target → $(readlink "$target")"
      elif [ -e "$target" ]; then
        echo "  WARN: $target exists (not symlink) — skipping"
      else
        ln -s "$symlink_target" "$target"
        echo "  symlink created: $target → $symlink_target"
      fi
    fi
    ;;

  merge-mcp)
    if $dry_run; then
      echo "  [DRY RUN] merge-mcp: $source → $target"
    else
      local tdir; tdir="$(dirname "$target")"
      mkdir -p "$tdir"
      cp "$source" "$target"
      echo "  merge-mcp: base → $target"
      echo "    (user MCP merge via /add-workspace-mcps skill)"
    fi
    ;;

  structure-only)
    if $dry_run; then
      echo "  [DRY RUN] structure-only: mkdir -p $target"
    else
      mkdir -p "$target" && echo "  structure-only: $target"
    fi
    ;;

  *)
    echo "  WARN: unknown strategy '$strategy' for $target" >&2
    return 1
    ;;
  esac
}

# =========================================================================
# apply_manifest — читает manifest и применяет все артефакты
# Usage: apply_manifest <manifest_path> <dry_run:true|false>
# =========================================================================
apply_manifest() {
  local manifest_file="$1"
  local dry_run="${2:-false}"

  _apply_callback() {
    local src="$1" tgt="$2" st="$3" sym="$4" ph="$5"
    # Expand variable in target path
    tgt="${tgt//\$WORKSPACE_FULL_PATH/$WORKSPACE_FULL_PATH}"
    apply_strategy "$src" "$tgt" "$st" "$sym" "$ph" "$dry_run"
  }

  parse_manifest "$manifest_file" _apply_callback
}
