#!/usr/bin/env bash
# template-sync.sh — синхронизация авторского IWE → FMT-exocortex-template
# Только для params.yaml → author_mode: true
# ADR-005 § «Авторский пайплайн»
#
# Usage:
#   bash template-sync.sh --check   Проверить что синхронизируется (без изменений)
#   bash template-sync.sh --sync    Синхронизировать (placeholder-подстановка + валидация)
#
# Pipeline:
#   1. Read author_paths from params.yaml
#   2. Copy files from IWE → FMT template
#   3. Substitute {{PLACEHOLDER}} tokens
#   4. Validate via setup/validate-template.sh
#   5. Report changes

set -euo pipefail

VERSION="0.1.0"
CHECK_ONLY=false
SYNC=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --sync) SYNC=true ;;
    --version) echo "template-sync v$VERSION"; exit 0 ;;
    --help | -h)
      echo "Usage: template-sync.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --check    Проверить что изменится (dry-run)"
      echo "  --sync     Синхронизировать IWE → FMT (placeholder подстановка)"
      echo "  --version  Версия скрипта"
      echo "  --help     Эта справка"
      exit 0
      ;;
  esac
done

if ! $CHECK_ONLY && ! $SYNC; then
  echo "Usage: template-sync.sh --check | --sync"
  echo "  --check   Preview sync changes"
  echo "  --sync    Apply sync"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === Cross-platform sed (via setup.sh helper) ===
if sed --version >/dev/null 2>&1; then
  sed_inplace() { sed -i "$@"; }
else
  sed_inplace() { sed -i '' "$@"; }
fi

# === Read author config ===
PARAMS_FILE="$ROOT_DIR/params.yaml"
if [ ! -f "$PARAMS_FILE" ]; then
  echo "ERROR: params.yaml not found. Run setup.sh first." >&2
  exit 3
fi

AUTHOR_MODE=$(grep 'author_mode:' "$PARAMS_FILE" 2>/dev/null | awk '{print $2}' || echo "false")
if [ "$AUTHOR_MODE" != "true" ]; then
  echo "ERROR: author_mode is not enabled in params.yaml" >&2
  echo "  Set author_mode: true to use template-sync.sh" >&2
  exit 3
fi

# === Placeholder mappings (author → template) ===
# Read from params.yaml or use defaults
GITHUB_USER="${GITHUB_USER:-$(grep 'github_user:' "$PARAMS_FILE" 2>/dev/null | awk '{print $2}' || echo "abcdef0101")}"
WORKSPACE_NAME="${WORKSPACE_NAME:-$(grep 'workspace_name:' "$PARAMS_FILE" 2>/dev/null | awk '{print $2}' || echo "iwe2")}"

echo "========================================="
echo " template-sync v$VERSION"
echo " Author mode: $AUTHOR_MODE"
echo "========================================="
echo ""

# === File mapping: IWE → FMT ===
# These are the template files that contain author-specific paths/names
# They get copied from the author IWE to the FMT template with placeholder substitution
declare -A SYNC_FILES
SYNC_FILES["CLAUDE.md"]="CLAUDE.md"
SYNC_FILES["ONTOLOGY.md"]="ONTOLOGY.md"
SYNC_FILES["CHANGELOG.md"]="CHANGELOG.md"
SYNC_FILES["seed/manifest.yaml"]="seed/manifest.yaml"
SYNC_FILES["extension-points.yaml"]="extension-points.yaml"

CHANGES=0
UPTODATE=0

for src in "${!SYNC_FILES[@]}"; do
  dst="${SYNC_FILES[$src]}"

  if [ ! -f "$ROOT_DIR/$src" ]; then
    echo "  - $src: not found (skip)"
    continue
  fi

  if $CHECK_ONLY; then
    # Compare: does the source differ from target after placeholder substitution?
    tmp_src=$(mktemp)
    cp "$ROOT_DIR/$src" "$tmp_src"

    # Reverse-substitute: replace author values with placeholders
    # {{GITHUB_USER}} → abcdef0101 in author's copy, need to reverse
    sed_inplace "s|$GITHUB_USER|{{GITHUB_USER}}|g" "$tmp_src" 2>/dev/null || true
    sed_inplace "s|$WORKSPACE_NAME|{{WORKSPACE_NAME}}|g" "$tmp_src" 2>/dev/null || true
    sed_inplace "s|$ROOT_DIR|{{ROOT_DIR}}|g" "$tmp_src" 2>/dev/null || true

    if [ -f "$ROOT_DIR/$dst" ]; then
      if diff -q "$tmp_src" "$ROOT_DIR/$dst" >/dev/null 2>&1; then
        echo "  ✓ $src (up to date)"
        UPTODATE=$((UPTODATE + 1))
      else
        echo "  ↑ $src (has changes)"
        diff "$tmp_src" "$ROOT_DIR/$dst" | head -15 | sed 's/^/    /'
        CHANGES=$((CHANGES + 1))
      fi
    else
      echo "  + $src (new file)"
      CHANGES=$((CHANGES + 1))
    fi

    rm -f "$tmp_src"
  else
    # --sync: apply
    tmp_synced=$(mktemp)
    cp "$ROOT_DIR/$src" "$tmp_synced"

    # Substitute author values → placeholders
    sed_inplace "s|$GITHUB_USER|{{GITHUB_USER}}|g" "$tmp_synced" 2>/dev/null || true
    sed_inplace "s|$WORKSPACE_NAME|{{WORKSPACE_NAME}}|g" "$tmp_synced" 2>/dev/null || true
    sed_inplace "s|$ROOT_DIR|{{ROOT_DIR}}|g" "$tmp_synced" 2>/dev/null || true

    cp "$tmp_synced" "$ROOT_DIR/$dst"
    rm -f "$tmp_synced"
    echo "  ↻ $src → $dst (synced)"
    CHANGES=$((CHANGES + 1))
  fi
done

echo ""
echo "---"
echo "  Changed: $CHANGES, Up-to-date: $UPTODATE"

# === Post-sync validation ===
if $SYNC && [ "$CHANGES" -gt 0 ]; then
  echo ""
  echo "Running template validation..."
  if [ -f "$ROOT_DIR/setup/validate-template.sh" ]; then
    if bash "$ROOT_DIR/setup/validate-template.sh" --quiet 2>/dev/null; then
      echo "  ✓ Validation passed"
    else
      echo "  ⚠ Validation found issues (review above)"
    fi
  fi

  echo ""
  echo "========================================="
  echo " Sync Complete"
  echo "========================================="
  echo ""
  echo "Next steps:"
  echo "  1. git diff    # review changes"
  echo "  2. git add -A && git commit -m \"sync: author IWE → template\""
  echo "  3. git push    # push to FMT-exocortex-template"
  echo ""
  echo "  After push, users run: bash update.sh --check && bash update.sh --apply"
fi

if $CHECK_ONLY && [ "$CHANGES" -gt 0 ]; then
  exit 1
fi
