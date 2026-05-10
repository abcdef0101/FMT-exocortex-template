#!/usr/bin/env bash
# verify-close.sh — механическая верификация чеклиста Quick Close / Day Close / Week Close
# Роль: R23 Верификатор (формальная проверка фактов, не качество — см. HD #40)
# Использование:
#   bash scripts/verify-close.sh                     # Quick Close / Day Close
#   bash scripts/verify-close.sh --week               # Week Close (DS-strategy repo)
#   bash scripts/verify-close.sh --checklist-only     # только вывод чеклиста
set -euo pipefail

MODE="${1:-close}"
ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WORKSPACE_DIR="${WORKSPACE_DIR:-}"

PASS=true
FAILED_ITEMS=""

_fail_item() {
  PASS=false
  FAILED_ITEMS="${FAILED_ITEMS}  - $1"$'\n'
}

# ---------------------------------------------------------------------------
# Чеклист Quick Close (6 пунктов)
# ---------------------------------------------------------------------------
check_quick_close() {
  echo "  [1/6] Commit — проверяем..."

  # 1. Есть ли коммит за последние 2 дня?
  if ! git -C "$ROOT_DIR" log -1 --format="%h %s" --since="2 days ago" | grep -q .; then
    _fail_item "Нет коммита за последние 2 дня"
  else
    echo "    ✓ коммит найден: $(git -C "$ROOT_DIR" log -1 --format='%h %s' --since='2 days ago')"
  fi

  echo "  [2/6] Push — проверяем..."

  # 2. Запушено?
  if git -C "$ROOT_DIR" status 2>/dev/null | grep -q "Your branch is ahead"; then
    _fail_item "Не запушено (branch ahead of remote)"
  elif git -C "$ROOT_DIR" status 2>/dev/null | grep -q "up to date"; then
    echo "    ✓ запушено (up to date)"
  else
    # Could be 'up to date' or unrelated — treat as ok if not ahead
    echo "    ~ статус push не определён (проверь вручную)"
  fi

  echo "  [3/6] KE — проверяем..."

  # 3. KE: «Что узнали» маршрутизировано?
  KE_FOUND=""
  if [ -n "$WORKSPACE_DIR" ] && [ -d "$WORKSPACE_DIR/memory/persistent-memory" ]; then
    KE_FOUND=$(find "$WORKSPACE_DIR/memory/persistent-memory" -newer "$ROOT_DIR/.git/COMMIT_EDITMSG" -type f 2>/dev/null | head -1)
  fi
  if [ -z "$KE_FOUND" ]; then
    # Check if memory/ directory has new files
    KE_FOUND=$(find . -path "*/memory/*" -newer "$ROOT_DIR/.git/COMMIT_EDITMSG" -type f 2>/dev/null | head -1)
  fi
  if [ -z "$KE_FOUND" ]; then
    # KE check is soft — not all sessions produce new knowledge
    echo "    ~ KE не обнаружено (возможно, «нет нового знания»)"
  else
    echo "    ✓ KE обнаружено: $(basename "$KE_FOUND")"
  fi

  # 3. KE: «Что узнали» маршрутизировано (или «нет нового знания»)?
  KE_FOUND=""

  # 4. WP Context: «Осталось» записано?
  echo "  [4/6] WP Context — проверяем..."
  WP_CTX=""
  if [ -n "$WORKSPACE_DIR" ]; then
    WP_CTX=$(find "$WORKSPACE_DIR/DS-strategy/inbox" -name "WP-*-context.md" -newer "$ROOT_DIR/.git/COMMIT_EDITMSG" 2>/dev/null | head -1)
  fi
  if [ -z "$WP_CTX" ]; then
    # fallback: check if any WP context was modified since last commit
    WP_CTX=$(find . -path "*/DS-strategy/inbox/WP-*-context.md" -newer "$ROOT_DIR/.git/COMMIT_EDITMSG" 2>/dev/null | head -1)
  fi
  if [ -z "$WP_CTX" ]; then
    _fail_item "WP Context не обновлён (нет изменённых WP-*context.md после последнего коммита)"
  else
    if grep -q "Осталось\|Done\|done" "$WP_CTX" 2>/dev/null; then
      echo "    ✓ WP Context обновлён: $(basename "$WP_CTX")"
    else
      _fail_item "WP Context без «Осталось»/Done: $(basename "$WP_CTX")"
    fi
  fi

  echo "  [5/6] MEMORY.md — проверяем..."

  # 4. MEMORY.md обновлён?
  if git -C "$ROOT_DIR" diff HEAD~1 -- MEMORY.md 2>/dev/null | grep -q "^+"; then
    echo "    ✓ MEMORY.md изменён"
  elif git -C "$ROOT_DIR" diff --cached -- MEMORY.md 2>/dev/null | grep -q "^+"; then
    echo "    ✓ MEMORY.md staged"
  elif [ -n "${WP_FOUND:-}" ]; then
    echo "    ~ MEMORY.md не изменён (но WP был создан — возможно MEMORY не требовалось)"
  else
    _fail_item "MEMORY.md не обновлён (нет новых строк в git diff)"
  fi

  echo "  [6/6] Decision log — проверяем..."

  # 5. Decision log точен?
  DECISION_LOG=$(find . -path "*/decisions/decision-log-*.md" -newer "$ROOT_DIR/.git/COMMIT_EDITMSG" 2>/dev/null | head -1)
  if [ -z "$DECISION_LOG" ]; then
    # Not necessarily a failure — some sessions have no decisions
    echo "    ~ decision log не изменялся (возможно, не было новых решений)"
  else
    echo "    ✓ decision log обновлён: $(basename "$DECISION_LOG")"
  fi
}

# ---------------------------------------------------------------------------
# Чеклист Day Close (расширенный, вызывается из day-close)
# ---------------------------------------------------------------------------
check_day_close() {
  check_quick_close

  echo "  [7/7] DayPlan итоги — проверяем..."

  # 6. DayPlan содержит «Итоги дня»?
  if [ -n "$WORKSPACE_DIR" ]; then
    DAYPLAN="$WORKSPACE_DIR/DS-strategy/governance/DayPlan.md"
  else
    DAYPLAN=$(find . -path "*/governance/DayPlan.md" | head -1)
  fi
  if [ -n "${DAYPLAN:-}" ] && [ -f "$DAYPLAN" ]; then
    if grep -q "Итоги дня\|Итоги" "$DAYPLAN" 2>/dev/null; then
      echo "    ✓ DayPlan содержит «Итоги дня»"
    else
      _fail_item "DayPlan без секции «Итоги дня»"
    fi
  else
    echo "    ~ DayPlan не найден (Day Close без workspace?)"
  fi
}

# ---------------------------------------------------------------------------
# Чеклист Week Close (DS-strategy репо)
# ---------------------------------------------------------------------------
check_week_close() {
  STRATEGY_REPO="${WORKSPACE_DIR:-$ROOT_DIR}/DS-strategy"
  if [ ! -d "$STRATEGY_REPO" ]; then
    _fail_item "DS-strategy репо не найден: $STRATEGY_REPO"
  else
    echo "  [1/3] Commit (DS-strategy) — проверяем..."
    if ! git -C "$STRATEGY_REPO" log -1 --format="%h %s" --since="7 days ago" | grep -q .; then
      _fail_item "Нет коммита в DS-strategy за последние 7 дней"
    else
      echo "    ✓ коммит: $(git -C "$STRATEGY_REPO" log -1 --format='%h %s' --since='7 days ago')"
    fi

    echo "  [2/3] Push (DS-strategy) — проверяем..."
    if git -C "$STRATEGY_REPO" status 2>/dev/null | grep -q "Your branch is ahead"; then
      _fail_item "DS-strategy не запушен (ahead of remote)"
    else
      echo "    ✓ запушено или up-to-date"
    fi

    echo "  [3/3] WeekPlan — проверяем..."
    WEEKPLAN="$STRATEGY_REPO/governance/WeekPlan.md"
    if [ -f "$WEEKPLAN" ] && grep -q "Итоги W" "$WEEKPLAN" 2>/dev/null; then
      echo "    ✓ WeekPlan содержит «Итоги»"
    else
      _fail_item "WeekPlan без секции «Итоги»"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$MODE" in
  --checklist-only)
    echo "## Чеклист формальной верификации (R23)"
    echo ""
    echo "- [ ] Commit (за последние 2 дня)"
    echo "- [ ] Push (up to date или ahead, не отстаёт)"
    echo "- [ ] KE: новое знание в memory/persistent-memory"
    echo "- [ ] WP Context: «Осталось» записано (или done)"
    echo "- [ ] MEMORY.md: статус РП обновлён"
    echo "- [ ] Decision log: обновлён или не требовался"
    exit 0
    ;;
  --week)
    echo "=== R23 Верификация (Week Close) ==="
    check_week_close
    ;;
  --day)
    echo "=== R23 Верификация (Day Close) ==="
    check_day_close
    ;;
  *)
    echo "=== R23 Верификация (Quick Close) ==="
    check_quick_close
    ;;
esac

echo ""
if [ "$PASS" = true ]; then
  echo "✓ Верификация пройдена."
  exit 0
else
  echo "✗ Верификация НЕ пройдена:"
  echo "$FAILED_ITEMS"
  exit 1
fi
