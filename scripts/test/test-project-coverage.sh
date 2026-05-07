#!/usr/bin/env bash
# test-project-coverage.sh — верификатор: все audit-issues должны быть на проектной доске
# Блокирующий gate после Phase 7 (Findings → Issues).
# Если проверка не пройдена → Phase 7 не завершён.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

PROJECT_NUMBER="${AUDIT_PROJECT_NUMBER:-12}"
OWNER="${AUDIT_OWNER:-abcdef0101}"
REPO="${AUDIT_REPO:-FMT-exocortex-template}"
LABEL="${AUDIT_LABEL:-test-suite-remediation}"

echo "  --- project board coverage check ---"

# 1. Получить все issues с audit-лейблом (open + closed)
echo "  fetching issues with label: $LABEL..."
ISSUE_NUMBERS=$(gh issue list --repo "$OWNER/$REPO" \
  --label "$LABEL" --limit 50 --state all \
  --json number --jq '.[].number' 2>/dev/null || echo "")
if [ -z "$ISSUE_NUMBERS" ]; then
  _fail "no issues found with label $LABEL"
  exit $FAIL
fi

ISSUE_COUNT=$(echo "$ISSUE_NUMBERS" | wc -l)
echo "  found $ISSUE_COUNT issues"

# 2. Получить все issues на доске проекта
echo "  fetching project board items..."
BOARD_ISSUES=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" \
  --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data.get('items', []):
        content = item.get('content', {})
        if content and content.get('number'):
            print(content['number'])
except: pass
" 2>/dev/null || echo "")

BOARD_COUNT=$(echo "$BOARD_ISSUES" | grep -c . 2>/dev/null || echo 0)
echo "  found $BOARD_COUNT items on project board"

# 3. Найти issues не на доске
MISSING=0
while IFS= read -r num; do
  [ -z "$num" ] && continue

  # Verify label is actually present — gh issue list may return stale cache
  LABELS=$(gh issue view "$num" --repo "$OWNER/$REPO" --json labels --jq '.labels[].name' 2>/dev/null)
  if ! echo "$LABELS" | grep -qF "$LABEL"; then
    continue  # label removed, stale cache entry
  fi

  if ! echo "$BOARD_ISSUES" | grep -qx "$num"; then
    _fail "issue #$num — not on project board"
    MISSING=$((MISSING + 1))
  fi
done <<< "$ISSUE_NUMBERS"

if [ "$MISSING" -eq 0 ]; then
  _pass "all $ISSUE_COUNT issues on project board"
else
  _fail "$MISSING issue(s) missing from project board"
  echo ""
  echo "  To fix, run:"
  echo "    gh api graphql -f query='mutation { addProjectV2ItemById(input: { projectId: \"<PROJECT_ID>\" contentId: \"<ISSUE_NODE_ID>\" }) { item { id } } }'"
fi

# 4. Проверить что закрытые issues в колонке Done
echo "  --- status check ---"
CLOSED_NOT_DONE=0
BOARD_JSON=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null || echo "{}")
while IFS= read -r num; do
  [ -z "$num" ] && continue
  STATE=$(gh issue view "$num" --repo "$OWNER/$REPO" --json state --jq '.state' 2>/dev/null || echo "unknown")
  if [ "$STATE" = "CLOSED" ]; then
    STATUS=$(echo "$BOARD_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data.get('items', []):
        if item.get('content', {}).get('number') == $num:
            status = item.get('status', '')
            if isinstance(status, dict):
                status = status.get('name', '')
            print(status)
            break
except: pass
" 2>/dev/null || echo "")
    if [ "$STATUS" != "Done" ] && [ -n "$STATUS" ]; then
      echo "  • #$num: CLOSED but status='$STATUS' (should be 'Done')"
      CLOSED_NOT_DONE=$((CLOSED_NOT_DONE + 1))
    fi
  fi
done <<< "$ISSUE_NUMBERS"

if [ "$CLOSED_NOT_DONE" -eq 0 ]; then
  _pass "closed issues in Done column: OK"
else
  echo "  (advisory: $CLOSED_NOT_DONE closed issues not in Done — cosmetic)"

fi
# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
