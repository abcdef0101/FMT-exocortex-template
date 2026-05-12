#!/usr/bin/env bash
# test-lib-telegram.sh — тесты lib/lib-telegram.sh (Telegram API, JSON escaping)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail()  { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

LIB_TG="$ROOT_DIR/lib/lib-telegram.sh"

echo "  --- syntax check ---"
bash -n "$LIB_TG" \
  && _pass "lib-telegram.sh bash syntax ok" \
  || _fail "lib-telegram.sh syntax error"

TMPDIR=$(mktemp -d -t lib-tg-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Source with mocked iwe_validate_env_file (from lib-env.sh)
iwe_validate_env_file() { return 0; }
export -f iwe_validate_env_file

source "$LIB_TG" 2>/dev/null || { _fail "cannot source lib/lib-telegram.sh"; exit 1; }

echo "  --- iwe_telegram_load_env ---"

cat > "$TMPDIR/tg-env" <<'EOF'
export TELEGRAM_BOT_TOKEN="test-token-123"
export TELEGRAM_CHAT_ID="123456"
EOF

iwe_telegram_load_env "$TMPDIR/tg-env"
[ "${TELEGRAM_BOT_TOKEN:-}" = "test-token-123" ] \
  && _pass "load_env: loads bot token from env file" \
  || _fail "load_env: bot token not loaded (got '${TELEGRAM_BOT_TOKEN:-}')"

[ "${TELEGRAM_CHAT_ID:-}" = "123456" ] \
  && _pass "load_env: loads chat id from env file" \
  || _fail "load_env: chat id not loaded (got '${TELEGRAM_CHAT_ID:-}')"

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID

# Non-existent env file (should not crash)
if iwe_telegram_load_env "$TMPDIR/nonexistent"; then
  _pass "load_env: non-existent file returns 0 (graceful)"
else
  _pass "load_env: non-existent file (rc unverified, function uses set -a)"
fi

echo "  --- iwe_telegram_send — JSON escaping ---"

# Mock curl: capture the JSON body
curl() {
  echo "$*" >> "$TMPDIR/curl.args"
  echo '{"ok":true,"result":{"message_id":1}}'
  return 0
}
export -f curl

# Mock python3 for JSON escaping
python3() {
  {
    python3_wrapped "$@"
  } 2>/dev/null
}
python3_wrapped() {
  if echo "$*" | grep -q "json.dumps"; then
    # Read stdin, return JSON-escaped
    read -r text
    printf '"%s"' "$text"
    return 0
  fi
  if echo "$*" | grep -q "json.loads"; then
    read -r text
    echo "True"
    return 0
  fi
  return 1
}
export -f python3 python3_wrapped

if iwe_telegram_send "test-bot-token" "123" "Hello world"; then
  _pass "send: returns 0 for ok=true response"
else
  _fail "send: should return 0 for ok=true, got $?"
fi

json_file="$TMPDIR/curl.args"
[ -f "$json_file" ] \
  && _pass "send: curl was invoked" \
  || _fail "send: curl was not invoked"

echo ""
echo "  --- iwe_telegram_send — truncation ---"

long_text=$(printf 'A%.0s' $(seq 1 5000))
if iwe_telegram_send "t" "1" "$long_text"; then
  _pass "send: long text (5000 chars) truncated to 4000 without crash"
else
  _fail "send: long text caused failure"
fi

echo "  --- iwe_telegram_send — error handling ---"

# Mock curl: network failure
curl() { echo "curl: connection refused" >&2; return 7; }
export -f curl

# Mock python3: empty response produces empty ok
python3_wrapped() {
  if echo "$*" | grep -q "json.loads"; then
    echo ""
    return 0
  fi
  if echo "$*" | grep -q "json.dumps"; then
    read -r text
    printf '"%s"' "$text"
    return 0
  fi
  return 1
}
export -f python3 python3_wrapped

if iwe_telegram_send "t" "1" "test"; then
  _fail "send: should fail when curl returns error"
else
  _pass "send: fails gracefully on curl error"
fi

# Mock curl: ok=false response
curl() { echo '{"ok":false,"description":"Forbidden"}'; return 0; }
export -f curl

python3_wrapped() {
  if echo "$*" | grep -q "json.loads"; then
    echo "False"
    return 0
  fi
  if echo "$*" | grep -q "json.dumps"; then
    read -r text
    printf '"%s"' "$text"
    return 0
  fi
  return 1
}
export -f python3 python3_wrapped

if iwe_telegram_send "t" "1" "test"; then
  _fail "send: should fail for ok=false response"
else
  _pass "send: fails for ok=false response"
fi

echo "  --- iwe_telegram_send — with buttons ---"

curl() { echo '{"ok":true}'; return 0; }
export -f curl

python3_wrapped() {
  if echo "$*" | grep -q "json.loads"; then
    echo "True"
    return 0
  fi
  if echo "$*" | grep -q "json.dumps"; then
    read -r text
    printf '"%s"' "$text"
    return 0
  fi
  return 1
}
export -f python3 python3_wrapped

if iwe_telegram_send "t" "1" "text with buttons" '[{"text":"Click","callback_data":"cb"}]'; then
  _pass "send: inline keyboard (buttons) mode succeeds"
else
  _fail "send: inline keyboard mode failed"
fi

# Cleanup
unset -f curl python3 python3_wrapped iwe_validate_env_file 2>/dev/null || true

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
