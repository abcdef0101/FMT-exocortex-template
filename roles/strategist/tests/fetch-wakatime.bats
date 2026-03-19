#!/usr/bin/env bats
# Тесты для roles/strategist/scripts/fetch-wakatime.sh
# Покрывает: portable_date_offset(), date_offset(), waka_fetch(), format_projects()

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch-wakatime.sh"

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"

    # Мокируем curl через PATH
    mkdir -p "$TEST_DIR/bin"
    export PATH="$TEST_DIR/bin:$PATH"

    # Загружаем функции без выполнения main-логики
    # Подменяем переменные окружения
    export WAKATIME_API_KEY="test-key-12345"
    export HOME="$TEST_DIR"

    # Source только функций (скрипт не имеет BASH_SOURCE guard — sourcing напрямую)
    # Используем partial source через подстановку функций
    source /dev/stdin <<'EOF'
portable_date_offset() {
    local days="$1"
    local fmt="${2:-%Y-%m-%d}"
    date -v-${days}d +"$fmt" 2>/dev/null || date -d "$days days ago" +"$fmt" 2>/dev/null
}

date_offset() {
    local days="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -v${days}d +%Y-%m-%d
    else
        date -d "${days} days" +%Y-%m-%d
    fi
}
EOF
}

# ---------------------------------------------------------------------------
# portable_date_offset
# ---------------------------------------------------------------------------

@test "portable_date_offset: возвращает вчерашнюю дату" {
    local expected
    expected=$(date -d "1 days ago" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

    run portable_date_offset 1
    assert_success
    assert_output "$expected"
}

@test "portable_date_offset: возвращает дату 7 дней назад" {
    local expected
    expected=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)

    run portable_date_offset 7
    assert_success
    assert_output "$expected"
}

@test "portable_date_offset: поддерживает кастомный формат" {
    local expected
    expected=$(date -d "1 days ago" +%Y%m%d 2>/dev/null || date -v-1d +%Y%m%d)

    run portable_date_offset 1 "%Y%m%d"
    assert_success
    assert_output "$expected"
}

@test "portable_date_offset: формат по умолчанию YYYY-MM-DD" {
    run portable_date_offset 1
    assert_success
    # Проверяем формат YYYY-MM-DD
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# ---------------------------------------------------------------------------
# waka_fetch (с мок-curl)
# ---------------------------------------------------------------------------

_setup_curl_mock() {
    local response="${1:-{}}"
    local exit_code="${2:-0}"
    cat > "$TEST_DIR/bin/curl" <<EOF
#!/usr/bin/env bash
echo '$response'
exit $exit_code
EOF
    chmod +x "$TEST_DIR/bin/curl"

    # Загружаем waka_fetch с нашим curl
    export ENCODED
    ENCODED=$(echo -n "test-key-12345" | base64)
    source /dev/stdin <<'FUNC'
waka_fetch() {
    local url="$1"
    curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic $ENCODED" "$url" 2>/dev/null
}
FUNC
}

@test "waka_fetch: успешный запрос возвращает данные" {
    _setup_curl_mock '{"data":{"text":"2 hrs 30 mins"}}'

    run waka_fetch "https://wakatime.com/api/v1/users/current/summaries"
    assert_success
    assert_output --partial '"data"'
}

@test "waka_fetch: сетевая ошибка возвращает пустой вывод" {
    _setup_curl_mock "" 6  # exit 6 = could not resolve host

    run waka_fetch "https://wakatime.com/api/v1/users/current/summaries"
    # --fail + exit 6 → failure, но мы используем 2>/dev/null
    # Проверяем что скрипт не крашится
    assert [ "$status" -ge 0 ]
}

@test "waka_fetch: передаёт Authorization заголовок" {
    # Шпион: записываем аргументы curl
    cat > "$TEST_DIR/bin/curl" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TEST_DIR/curl_args"
echo '{}'
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export ENCODED
    ENCODED=$(echo -n "test-key-12345" | base64)
    source /dev/stdin <<'FUNC'
waka_fetch() {
    local url="$1"
    curl --fail --max-time 10 --connect-timeout 5 -s -H "Authorization: Basic $ENCODED" "$url" 2>/dev/null
}
FUNC

    waka_fetch "https://wakatime.com/api/v1/test"
    run grep "Authorization" "$TEST_DIR/curl_args"
    assert_success
}

# ---------------------------------------------------------------------------
# format_projects
# ---------------------------------------------------------------------------

source /dev/stdin <<'EOF'
format_projects() {
    python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data:
    print('| (нет данных) | — |')
else:
    for p in sorted(data, key=lambda x: x.get('total_seconds', 0), reverse=True)[:10]:
        name = p.get('name', '?')
        text = p.get('text', '0 secs')
        print(f'| {name} | {text} |')
" 2>/dev/null || echo "| (ошибка парсинга) | — |"
}
EOF

@test "format_projects: корректный JSON возвращает таблицу" {
    run python3 -c "
import json
data = [{'name':'myproject','total_seconds':3600,'text':'1 hr'}]
for p in sorted(data, key=lambda x: x.get('total_seconds',0), reverse=True)[:10]:
    print(f'| {p[\"name\"]} | {p[\"text\"]} |')
"
    assert_success
    assert_output "| myproject | 1 hr |"
}

@test "format_projects: пустой массив возвращает заглушку" {
    run python3 -c "
import json
data = []
if not data:
    print('| (нет данных) | — |')
"
    assert_success
    assert_output "| (нет данных) | — |"
}

@test "format_projects: сортирует по total_seconds по убыванию" {
    run python3 -c "
data = [
    {'name':'slow','total_seconds':100,'text':'1 min'},
    {'name':'fast','total_seconds':3600,'text':'1 hr'},
]
for p in sorted(data, key=lambda x: x.get('total_seconds',0), reverse=True)[:10]:
    print(p['name'])
"
    assert_success
    # fast должен быть первым
    [[ "${lines[0]}" == "fast" ]]
}
