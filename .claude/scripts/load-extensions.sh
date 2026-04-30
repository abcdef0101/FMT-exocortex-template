#!/bin/bash
# load-extensions.sh — universal loader для suffix extensions с поддержкой --sub-dir.
#
# Сканирует $WORKSPACE_DIR/extensions/<sub-dir>/ на файлы:
#   <protocol>.<hook>.md + <protocol>.<hook>.<suffix>.md
# Возвращает отсортированный список путей (exit 0) или exit 1 если файлов нет.
#
# Usage:
#   bash load-extensions.sh <protocol> <hook> [--sub-dir <dir>]
#   bash load-extensions.sh day-close after
#   bash load-extensions.sh protocol-close checks --sub-dir protocol-hooks

set -eu

SUB_DIR="protocol-hooks"
PROTOCOL=""
HOOK=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sub-dir) SUB_DIR="$2"; shift 2 ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        -* ) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)
            if [ -z "$PROTOCOL" ]; then PROTOCOL="$1"; shift
            elif [ -z "$HOOK" ]; then HOOK="$1"; shift
            else shift; fi
            ;;
    esac
done

if [ -z "$PROTOCOL" ] || [ -z "$HOOK" ]; then
    echo "Usage: load-extensions.sh <protocol> <hook> [--sub-dir <dir>]" >&2
    echo "Example: load-extensions.sh day-close after --sub-dir protocol-hooks" >&2
    exit 2
fi

# Resolve workspace if not already set by calling skill
if [ -z "${WORKSPACE_DIR:-}" ]; then
    # shellcheck source=resolve-workspace.sh
    source "$(dirname "${BASH_SOURCE[0]}")/resolve-workspace.sh"
    if resolve_fmt_dir; then resolve_workspace; fi
fi

if [ -z "${WORKSPACE_DIR:-}" ]; then
    echo "ERROR: Cannot resolve workspace directory" >&2
    exit 1
fi

EXT_DIR="$WORKSPACE_DIR/extensions/$SUB_DIR"
if [ ! -d "$EXT_DIR" ]; then
    exit 1
fi

# Glob: <protocol>.<hook>.md OR <protocol>.<hook>.<suffix>.md
FOUND=$(find "$EXT_DIR" -maxdepth 1 -type f \
    \( -name "${PROTOCOL}.${HOOK}.md" -o -name "${PROTOCOL}.${HOOK}.*.md" \) 2>/dev/null | sort)

if [ -z "$FOUND" ]; then
    exit 1
fi

echo "$FOUND"
exit 0
