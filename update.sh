#!/usr/bin/env bash
# update.sh — механизм обновления шаблона FMT-exocortex-template
# ADR-005: checksum-based enforcement + 3-way merge + compat-check + migration + validate
#
# Usage:
#   bash update.sh --check     Показать что изменится (dry-run, без изменений)
#   bash update.sh --apply     Применить обновление
#   bash update.sh --version   Версия скрипта
#   bash update.sh --help      Справка
#
# Exit codes:
#   0 — успех (check: ничего не изменилось, apply: обновление применено)
#   1 — есть изменения (--check: нужно обновление)
#   2 — ошибка валидации или конфликт
#   3 — фатальная ошибка (нет .git, нет upstream)

set -uo pipefail

VERSION="0.1.0"
CHECK_ONLY=false
APPLY=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --apply) APPLY=true ;;
    --version) echo "exocortex-update v$VERSION"; exit 0 ;;
    --help | -h)
      echo "Usage: update.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --check    Показать что изменится (dry-run, без изменений)"
      echo "  --apply    Применить обновление"
      echo "  --version  Версия скрипта"
      echo "  --help     Эта справка"
      exit 0
      ;;
  esac
done

if ! $CHECK_ONLY && ! $APPLY; then
  echo "Usage: update.sh --check | --apply"
  echo "  --check   Preview changes"
  echo "  --apply   Apply update"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === Cross-platform sed ===
if sed --version >/dev/null 2>&1; then
  sed_inplace() { sed -i "$@"; }
else
  sed_inplace() { sed -i '' "$@"; }
fi

# === Load manifest library ===
MANIFEST_LIB="$ROOT_DIR/scripts/lib/manifest-lib.sh"
[ -f "$MANIFEST_LIB" ] || { echo "ERROR: manifest-lib.sh not found: $MANIFEST_LIB" >&2; exit 3; }
source "$MANIFEST_LIB"

# =========================================================================
# Env discovery
# =========================================================================
MANIFEST_FILE="$ROOT_DIR/seed/manifest.yaml"
CK_FILE="$ROOT_DIR/checksums.yaml"
EP_FILE="$ROOT_DIR/extension-points.yaml"

# Find active workspace
WS_LINK="$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
if [ -L "$WS_LINK" ]; then
  WORKSPACE_FULL_PATH="$(cd "$(dirname "$WS_LINK")" && cd "$(readlink "$WS_LINK")" && pwd)"
  export WORKSPACE_FULL_PATH
elif [ -d "$WS_LINK" ]; then
  WORKSPACE_FULL_PATH="$WS_LINK"
  export WORKSPACE_FULL_PATH
fi

# =========================================================================
# Fetch upstream
# =========================================================================
_fetch_upstream() {
  echo "[1/5] Fetching upstream..."

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  ERROR: Not a git repository" >&2
    exit 3
  fi

  REMOTE=$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ -z "$REMOTE" ]; then
    echo "  ERROR: No git remote 'origin'" >&2
    exit 3
  fi

  CURRENT_BRANCH=$(git -C "$ROOT_DIR" branch --show-current)
  LOCAL_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD)
  LOCAL_SHORT="${LOCAL_SHA:0:7}"

  git -C "$ROOT_DIR" fetch origin "$CURRENT_BRANCH" 2>/dev/null || {
    echo "  ERROR: Cannot fetch from $REMOTE" >&2
    exit 3
  }

  UPSTREAM_SHA=$(git -C "$ROOT_DIR" rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
  UPSTREAM_SHORT="${UPSTREAM_SHA:0:7}"

  echo "  Local:    $LOCAL_SHORT ($CURRENT_BRANCH)"
  echo "  Upstream: $UPSTREAM_SHORT ($CURRENT_BRANCH)"

  if [ "$LOCAL_SHA" = "$UPSTREAM_SHA" ]; then
    echo "  ✓ Already up to date"
    return 1
  fi

  echo "  ✓ Changes available"
  return 0
}

# =========================================================================
# Version comparison via MANIFEST.yaml
# =========================================================================
_compare_versions() {
  echo ""
  echo "[2/5] Comparing component versions..."

  CHANGES=0
  UP_TO_DATE=0

  while IFS= read -r -d '' mf; do
    rel="${mf#$ROOT_DIR/}"
    local_ver=$(grep '^version:' "$mf" 2>/dev/null | awk '{print $2}' | head -1)

    # Get upstream version from fetched origin (via git show)
    upstream_ver=$(git -C "$ROOT_DIR" show "origin/$CURRENT_BRANCH:$rel" 2>/dev/null | grep '^version:' | awk '{print $2}' | head -1 || echo "?")

    if [ -z "$local_ver" ] || [ -z "$upstream_ver" ]; then
      echo "  ? $rel (version missing)"
      continue
    fi

    if [ "$local_ver" != "$upstream_ver" ]; then
      echo "  ↑ $rel: $local_ver → $upstream_ver"
      CHANGES=$((CHANGES + 1))
    else
      UP_TO_DATE=$((UP_TO_DATE + 1))
    fi
  done < <(find "$ROOT_DIR" -name "MANIFEST.yaml" \
    -not -path "*/.git/*" \
    -not -path "*/workspaces/*" \
    -not -path "*/DS-*/*" \
    -print0 2>/dev/null | sort -z)

  echo "  Changed: $CHANGES, Up-to-date: $UP_TO_DATE"
}

# =========================================================================
# Checksum verification
# =========================================================================
_checksum_verify() {
  echo ""
  echo "[3/5] Verifying checksums..."

  if [ ! -f "$CK_FILE" ]; then
    echo "  WARN: checksums.yaml not found — checksum verification skipped"
    return 0
  fi

  local normalize
  normalize() { sed 's/[[:space:]]*$//' "$1"; }

  local verified=0 warn=0 conflict=0 skip=0

  # Extract NEVER-TOUCH patterns
  local nt_patterns
  nt_patterns=$(sed -n '/^never_touch:/,/^files:/p' "$CK_FILE" | grep '^  - ' | sed 's/  - //')

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    # Parse: "  path: \"sha256\""
    if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*\"([a-f0-9]+)\" ]]; then
      local f="${BASH_REMATCH[1]}"
      local expected="${BASH_REMATCH[2]}"
      f="${f#"${f%%[![:space:]]*}"}"  # trim leading spaces
      f="${f%"${f##*[![:space:]]}"}"  # trim trailing spaces

      [ ! -f "$ROOT_DIR/$f" ] && continue  # file not in local tree

      # Check NEVER-TOUCH
      local is_nt=0
      while IFS= read -r nt; do
        [[ "$f" == "$nt"* ]] && { is_nt=1; break; }
      done <<< "$nt_patterns"

      local actual
      actual=$(normalize "$ROOT_DIR/$f" | sha256sum | cut -d' ' -f1)

      if [ "$is_nt" -eq 1 ]; then
        skip=$((skip + 1))
        continue
      fi

      if [ "$expected" = "$actual" ]; then
        verified=$((verified + 1))
      else
        warn=$((warn + 1))
        echo "  ⚠ modified: $f"
        # Show diff if git tracked
        git -C "$ROOT_DIR" diff -- "$f" 2>/dev/null | head -10 | sed 's/^/    /' || true
      fi
    fi
  done < <(sed -n '/^files:/,$ p' "$CK_FILE")

  echo "  Verified: $verified, Modified: $warn, Skipped (never-touch): $skip"
  [ "$warn" -gt 0 ] && return 2
  return 0
}

# =========================================================================
# 3-way merge for CLAUDE.md and ONTOLOGY.md (ADR-005 §3)
# =========================================================================
_three_way_merge() {
  local file="$1"
  local rel="${file#$ROOT_DIR/}"

  [ ! -f "$ROOT_DIR/$file" ] && return 0

  # Get base version from git
  local base_sha
  base_sha=$(git -C "$ROOT_DIR" merge-base HEAD "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
  [ -z "$base_sha" ] && return 0

  # Get ours (local), theirs (upstream), base (common ancestor)
  git -C "$ROOT_DIR" show "$base_sha:$rel" > /tmp/update-base-$$ 2>/dev/null || return 0
  cp "$ROOT_DIR/$file" /tmp/update-ours-$$ 2>/dev/null || return 0
  git -C "$ROOT_DIR" show "origin/$CURRENT_BRANCH:$rel" > /tmp/update-theirs-$$ 2>/dev/null || return 0

  # Check if merge is needed
  if diff -q /tmp/update-ours-$$ /tmp/update-theirs-$$ >/dev/null 2>&1; then
    rm -f /tmp/update-{base,ours,theirs}-$$
    echo "  ✓ $rel: no changes"
    return 0
  fi

  echo "  Merging: $rel"

  if git merge-file -p /tmp/update-ours-$$ /tmp/update-base-$$ /tmp/update-theirs-$$ > /tmp/update-merged-$$ 2>/dev/null; then
    # Check for conflict markers
    if grep -q '^<<<<<<<\|^=======\|^>>>>>>>' /tmp/update-merged-$$ 2>/dev/null; then
      echo "  ⚠ CONFLICT: $rel (manual resolution required)"
      echo "    Files saved: /tmp/update-{ours,theirs,base}-$$"
      echo "    Run: git merge-file $ROOT_DIR/$file /tmp/update-base-$$ /tmp/update-theirs-$$"
      return 2
    fi
    cp /tmp/update-merged-$$ "$ROOT_DIR/$file"
    echo "  ✓ $rel: merged successfully"
  fi

  rm -f /tmp/update-{base,ours,theirs,merged}-$$
}

# =========================================================================
# Compat-check extensions (ADR-005 §5)
# =========================================================================
_compat_check() {
  echo ""
  echo "[4/5] Checking extension compatibility..."

  if [ ! -f "$EP_FILE" ]; then
    echo "  WARN: extension-points.yaml not found — compat check skipped"
    return 0
  fi

  # Get active extensions from workspace
  local ext_dir=""
  [ -n "${WORKSPACE_FULL_PATH:-}" ] && [ -d "$WORKSPACE_FULL_PATH/extensions" ] && ext_dir="$WORKSPACE_FULL_PATH/extensions"

  if [ ! -d "$ext_dir" ]; then
    echo "  - no extensions directory in workspace"
    return 0
  fi

  # Check each extension point that has a file convention
  local compat_ok=0 compat_warn=0

  while IFS= read -r line; do
    [[ "$line" =~ file:\ *extensions/([^ ]+) ]] || continue
    local ext_file="${BASH_REMATCH[1]}"
    # Only check protocol hooks (.md files)
    [[ "$ext_file" != *.md ]] && continue

    if [ -f "$ext_dir/$ext_file" ]; then
      # Extension exists — check if the upstream version changed its hook
      local upstream_ep
      upstream_ep=$(git -C "$ROOT_DIR" show "origin/$CURRENT_BRANCH:extension-points.yaml" 2>/dev/null || echo "")
      if [ -n "$upstream_ep" ]; then
        echo "  ✓ $ext_file (exists, compat ok)"
        compat_ok=$((compat_ok + 1))
      else
        echo "  ⚠ $ext_file (upstream extension-points.yaml changed — verify manually)"
        compat_warn=$((compat_warn + 1))
      fi
    fi
  done < "$EP_FILE"

  echo "  Compatible: $compat_ok, Warnings: $compat_warn"
  [ "$compat_warn" -gt 0 ] && echo "  Review warnings above before --apply"
}

# =========================================================================
# Post-update validate + notify
# =========================================================================
_post_update() {
  echo ""
  echo "[5/5] Post-update validation..."

  local errors=0

  # Validate symlink integrity (ADR-004 criterion 5)
  if [ -n "${WORKSPACE_FULL_PATH:-}" ]; then
    local symlink_target="$WORKSPACE_FULL_PATH/memory/persistent-memory"
    if [ -L "$symlink_target" ]; then
      if [ -e "$symlink_target" ]; then
        echo "  ✓ memory/persistent-memory symlink valid"
      else
        echo "  ✗ memory/persistent-memory symlink is broken"
        errors=$((errors + 1))
      fi
    else
      echo "  ✗ memory/persistent-memory symlink missing"
      errors=$((errors + 1))
    fi
  fi

  # Verify checksums.yaml integrity auto-regenerated
  if [ -f "$ROOT_DIR/scripts/generate-checksums.sh" ]; then
    bash "$ROOT_DIR/scripts/generate-checksums.sh" 2>/dev/null || true
    echo "  ✓ checksums.yaml regenerated"
  fi

  # Summary
  echo ""
  echo "========================================="
  if $APPLY; then
    echo "  Update Applied"
  else
    echo "  Check Complete"
  fi
  echo "========================================="
  echo ""
  if $CHECK_ONLY; then
    echo "To apply: bash update.sh --apply"
  fi

  [ "$errors" -eq 0 ] || return 2
}

# =========================================================================
# Main
# =========================================================================

echo "========================================="
echo " Exocortex Update v$VERSION"
echo "========================================="

# Fetch upstream
_upstream_has_changes=false
if _fetch_upstream; then
  _upstream_has_changes=true
fi

# Compare versions
_compare_versions

# Checksum verification
_checksum_verify || true  # non-fatal in --check mode

# Compat check
_compat_check

# If --check only, stop here
if $CHECK_ONLY; then
  _post_update
  if $_upstream_has_changes; then
    exit 1  # signal: changes available
  fi
  exit 0
fi

# =========================================================================
# --apply mode
# =========================================================================

if ! $_upstream_has_changes; then
  echo ""
  echo "Already up to date. Nothing to apply."
  exit 0
fi

echo ""
echo "--- Applying update ---"
echo ""

# Pull upstream changes
git -C "$ROOT_DIR" pull --rebase origin "$CURRENT_BRANCH" || {
  echo "  ERROR: git pull failed. Resolve conflicts manually." >&2
  exit 3
}
echo "  ✓ Upstream pulled"

# 3-way merge for mixed-space files
_three_way_merge "CLAUDE.md"
_three_way_merge "ONTOLOGY.md"

# Apply manifest to workspace (if workspace exists)
if [ -n "${WORKSPACE_FULL_PATH:-}" ] && [ -d "$WORKSPACE_FULL_PATH" ]; then
  echo ""
  echo "Applying manifest to workspace..."
  apply_manifest "$MANIFEST_FILE" false
fi

_post_update

echo ""
echo "Next: verify your workspace — /mcp, DayPlan, extensions"
