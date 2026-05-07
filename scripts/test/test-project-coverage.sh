#!/usr/bin/env bash
# test-project-coverage.sh — верификатор: все audit-issues должны быть на проектной доске
# Блокирующий gate после Phase 7 (Findings → Issues).
# Если проверка не пройдена → Phase 7 не завершён.
set -euo pipefail

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# === Guards ===
if ! command -v python3 &>/dev/null; then
  _fail "python3 required but not installed"
  exit $FAIL
fi

OWNER="${AUDIT_OWNER:-}"
REPO="${AUDIT_REPO:-}"
if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
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

# === Helper: run python3, verify exit code and output non-empty ===
_py_parse() {
  # Usage: _py_parse <label> <json_input> <python_code>
  # Returns 0 + prints result on stdout. Returns 1 on failure (_fail already called).
  local label="$1" json_data="$2" py_code="$3"
  local result stderr_out rc
  stderr_out=$(mktemp -t py-err-XXXXXX)
  trap 'rm -f "$stderr_out"' RETURN
  result=$(printf '%s\n' "$json_data" | python3 -c "$py_code" 2>"$stderr_out") && rc=$? || rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "$label: python3 exit $rc"
    sed 's/^/    | /' "$stderr_out" >&2
    return 1
  fi
  if [ -s "$stderr_out" ]; then
    echo "  WARN: $label produced stderr:" >&2
    sed 's/^/    | /' "$stderr_out" >&2
  fi
  if [ -z "$result" ]; then
    _fail "$label: empty output (JSON structure may have changed)"
    return 1
  fi
  echo "$result"
  return 0
}

# === Step 1: fetch all issues with audit label (open + closed) ===
echo "  fetching issues with label: $LABEL..."
ISSUE_DATA=$(gh issue list --repo "$OWNER/$REPO" \
  --label "$LABEL" --limit 50 --state all \
  --json number,state 2>/dev/null || echo "")
if [ -z "$ISSUE_DATA" ]; then
  _fail "no issues found with label $LABEL"
  exit $FAIL
fi

# Single Python call: parse both issue numbers and state mapping
ISSUE_PARSED=$(_py_parse "issue-list" "$ISSUE_DATA" '
import sys, json
try:
    for i in json.load(sys.stdin):
        num = i["number"]
        state = i["state"]
        print(f"{num}\t{state}")
except json.JSONDecodeError as e:
    sys.stderr.write(f"JSON parse error: {e}\n")
    sys.exit(1)
except KeyError as e:
    sys.stderr.write(f"Missing field: {e}\n")
    sys.exit(1)
') || exit $FAIL
ISSUE_NUMBERS=$(echo "$ISSUE_PARSED" | cut -f1)
ISSUE_COUNT=$(echo "$ISSUE_NUMBERS" | wc -l)
echo "  found $ISSUE_COUNT issues"

# === Step 2: fetch project board data (once, reused) ===
echo "  fetching project board items..."
BOARD_RAW=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" \
  --format json 2>/dev/null || echo "")
if [ -z "$BOARD_RAW" ] || [ "$BOARD_RAW" = "{}" ]; then
  _fail "no items on project board #$PROJECT_NUMBER (gh auth ok?)"
  exit $FAIL
fi

# Single Python call: extract both issue numbers and status mapping
BOARD_PARSED=$(_py_parse "board-data" "$BOARD_RAW" '
import sys, json
try:
    for item in json.load(sys.stdin).get("items", []):
        c = item.get("content", {})
        num = c.get("number")
        if not num:
            continue
        # Extract status from fieldValues
        status = ""
        for fv in item.get("fieldValues", {}).get("nodes", []):
            if fv and fv.get("field", {}).get("name") == "Status":
                s = fv.get("name", "")
                if s:
                    status = s
                break
        print(f"{num}\t{status}")
except (json.JSONDecodeError, AttributeError, KeyError) as e:
    sys.stderr.write(f"Board JSON parse error: {e}\n")
    sys.exit(1)
') || exit $FAIL
BOARD_ISSUES=$(echo "$BOARD_PARSED" | cut -f1)
BOARD_COUNT=$(echo "$BOARD_ISSUES" | wc -l)
echo "  found $BOARD_COUNT items on project board"

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

  STATE=$(echo "$ISSUE_PARSED" | awk -F'\t' -v n="$num" '$1 == n { print $2 }')
  if [ "$STATE" = "CLOSED" ]; then
    STATUS=$(echo "$BOARD_PARSED" | awk -F'\t' -v n="$num" '$1 == n { print $2 }')
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
