#!/usr/bin/env bash
# test-project-coverage.sh — верификатор: все audit-issues должны быть на проектной доске
# Блокирующий gate после Phase 7 (Findings → Issues).
# Если проверка не пройдена → Phase 7 не завершён.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# P1-FIX: auto-detect repo from git remote, require python3
if ! command -v python3 &>/dev/null; then
  _fail "python3 required but not installed"
  exit $FAIL
fi

OWNER="${AUDIT_OWNER:-}"
REPO="${AUDIT_REPO:-}"
if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  # Prefer origin remote (user's fork); fallback to any remote
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || git remote get-url upstream 2>/dev/null || echo "")
  if [ -n "$REMOTE_URL" ]; then
    REPO_FULL=$(echo "$REMOTE_URL" | sed 's|.*github\.com[:/]||;s|\.git$||')
    OWNER="${OWNER:-${REPO_FULL%/*}}"
    REPO="${REPO:-${REPO_FULL#*/}}"
  fi
fi
if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  _fail "cannot detect repo (set AUDIT_OWNER/AUDIT_REPO or run from a git repo)"
  exit $FAIL
fi

PROJECT_NUMBER="${AUDIT_PROJECT_NUMBER:-12}"
LABEL="${AUDIT_LABEL:-test-suite-remediation}"

echo "  --- project board coverage check ---"
echo "  repo: $OWNER/$REPO  project: #$PROJECT_NUMBER  label: $LABEL"

# === Step 1: fetch all issues with audit label (open + closed) ===
echo "  fetching issues with label: $LABEL..."
ISSUE_DATA=$(gh issue list --repo "$OWNER/$REPO" \
  --label "$LABEL" --limit 50 --state all \
  --json number,state 2>/dev/null || echo "")
if [ -z "$ISSUE_DATA" ]; then
  _fail "no issues found with label $LABEL"
  exit $FAIL
fi

ISSUE_NUMBERS=$(echo "$ISSUE_DATA" | python3 -c '
import sys, json
try:
    for i in json.load(sys.stdin):
        print(i["number"])
except json.JSONDecodeError as e:
    sys.stderr.write(f"JSON parse error: {e}\n")
    sys.exit(1)
except KeyError as e:
    sys.stderr.write(f"Missing field: {e}\n")
    sys.exit(1)
')
ISSUE_COUNT=$(echo "$ISSUE_NUMBERS" | grep -c . 2>/dev/null || echo 0)
echo "  found $ISSUE_COUNT issues"

# Build a lookup: issue_number → state (for status check)
ISSUE_STATES=$(echo "$ISSUE_DATA" | python3 -c '
import sys, json
try:
    for i in json.load(sys.stdin):
        print(f"{i["number"]}={i["state"]}")
except json.JSONDecodeError as e:
    sys.stderr.write(f"JSON parse error: {e}\n")
    sys.exit(1)
except KeyError as e:
    sys.stderr.write(f"Missing field: {e}\n")
    sys.exit(1)
')

# === Step 2: fetch project board data (once, reused) ===
echo "  fetching project board items..."
BOARD_RAW=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" \
  --format json 2>/dev/null || echo "")
if [ -z "$BOARD_RAW" ] || [ "$BOARD_RAW" = "{}" ]; then
  _fail "no items on project board #$PROJECT_NUMBER (gh auth ok?)"
  exit $FAIL
fi

BOARD_ISSUES=$(echo "$BOARD_RAW" | python3 -c '
import sys, json
try:
    for item in json.load(sys.stdin).get("items", []):
        c = item.get("content", {})
        if c and c.get("number"):
            print(c["number"])
except (json.JSONDecodeError, AttributeError, KeyError) as e:
    sys.stderr.write(f"Board JSON parse error: {e}\n")
    sys.exit(1)
' 2>&1)

BOARD_COUNT=$(echo "$BOARD_ISSUES" | grep -c . 2>/dev/null || echo 0)
echo "  found $BOARD_COUNT items on project board"

# Board status lookup: issue_number → status_name
BOARD_STATUSES=$(echo "$BOARD_RAW" | python3 -c '
import sys, json
try:
    for item in json.load(sys.stdin).get("items", []):
        c = item.get("content", {})
        num = c.get("number")
        if not num:
            continue
        field = item.get("fieldValues", {}).get("nodes", [])
        status = ""
        for fv in field:
            if fv and fv.get("field", {}).get("name") == "Status":
                status = fv.get("name", "")
                break
        print(f"{num}={status}")
except (json.JSONDecodeError, AttributeError, KeyError) as e:
    sys.stderr.write(f"Board status parse error: {e}\n")
    sys.exit(1)
' || true)

# === Step 3: find issues NOT on board ===
MISSING=0
while IFS= read -r num; do
  [ -z "$num" ] && continue

  if ! echo "$BOARD_ISSUES" | grep -qx "$num"; then
    _fail "issue #$num — not on project board"
    MISSING=$((MISSING + 1))
  fi
done <<< "$ISSUE_NUMBERS"

if [ "$MISSING" -eq 0 ]; then
  _pass "all $ISSUE_COUNT issues on project board"
else
  _fail "$MISSING issue(s) missing from project board"
  echo "  To fix, run:"
  echo "    gh api graphql -f query='mutation { addProjectV2ItemById(input: { projectId: \"<PROJECT_ID>\" contentId: \"<ISSUE_NODE_ID>\" }) { item { id } } }'"
fi

# === Step 4: closed issues should be in Done column ===
echo "  --- status check ---"
CLOSED_NOT_DONE=0
while IFS= read -r num; do
  [ -z "$num" ] && continue

  STATE=$(echo "$ISSUE_STATES" | grep "^${num}=" | cut -d= -f2)
  if [ "$STATE" = "CLOSED" ]; then
    STATUS=$(echo "$BOARD_STATUSES" | grep "^${num}=" | cut -d= -f2)
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
