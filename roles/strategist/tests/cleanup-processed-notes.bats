#!/usr/bin/env bats
# Тесты для roles/strategist/scripts/cleanup-processed-notes.sh
# Покрывает: process_block(), интеграционные тесты очистки

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/cleanup-processed-notes.sh"

# ---------------------------------------------------------------------------
# setup: загружаем process_block() в изоляции
# ---------------------------------------------------------------------------

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"

    # Экспортируем process_block и глобальные переменные которые она использует
    KEEP_BLOCKS=""
    ARCHIVE_BLOCKS=""
    KEEP_COUNT=0
    ARCHIVE_COUNT=0

    source /dev/stdin <<'EOF'
KEEP_BLOCKS=""
ARCHIVE_BLOCKS=""
KEEP_COUNT=0
ARCHIVE_COUNT=0

process_block() {
    local block="$1"
    [ -z "$block" ] && return

    local first_line
    first_line=$(echo "$block" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if echo "$first_line" | grep -q '^\*\*'; then
        KEEP_BLOCKS="${KEEP_BLOCKS}${block}
---SEPARATOR---
"
        KEEP_COUNT=$((KEEP_COUNT + 1))
    elif echo "$first_line" | grep -q '🔄'; then
        KEEP_BLOCKS="${KEEP_BLOCKS}${block}
---SEPARATOR---
"
        KEEP_COUNT=$((KEEP_COUNT + 1))
    else
        ARCHIVE_BLOCKS="${ARCHIVE_BLOCKS}${block}
---SEPARATOR---
"
        ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
    fi
}
EOF
}

# ---------------------------------------------------------------------------
# process_block: правила сохранения
# ---------------------------------------------------------------------------

@test "process_block: жирный заголовок (**) → ОСТАВИТЬ" {
    process_block "**Новая идея**
Описание идеи"

    assert_equal "$KEEP_COUNT" 1
    assert_equal "$ARCHIVE_COUNT" 0
    [[ "$KEEP_BLOCKS" == *"**Новая идея**"* ]]
}

@test "process_block: заголовок с 🔄 → ОСТАВИТЬ" {
    process_block "🔄 Требует ревью
Какое-то содержимое"

    assert_equal "$KEEP_COUNT" 1
    assert_equal "$ARCHIVE_COUNT" 0
}

@test "process_block: обычный заголовок → АРХИВИРОВАТЬ" {
    process_block "Обработанная заметка
Содержимое которое уже в Pack"

    assert_equal "$KEEP_COUNT" 0
    assert_equal "$ARCHIVE_COUNT" 1
    [[ "$ARCHIVE_BLOCKS" == *"Обработанная заметка"* ]]
}

@test "process_block: пустой блок → игнорировать" {
    process_block ""

    assert_equal "$KEEP_COUNT" 0
    assert_equal "$ARCHIVE_COUNT" 0
}

@test "process_block: несколько блоков — счётчики суммируются" {
    process_block "**Новая идея 1**
Описание"
    process_block "Обработано 1
Контент"
    process_block "🔄 На ревью
Контент"
    process_block "Обработано 2
Контент"

    assert_equal "$KEEP_COUNT" 2
    assert_equal "$ARCHIVE_COUNT" 2
}

@test "process_block: жирный текст НЕ в первой строке → АРХИВИРОВАТЬ" {
    # Только первая строка проверяется
    process_block "Обычный заголовок
**жирный текст** посередине"

    assert_equal "$KEEP_COUNT" 0
    assert_equal "$ARCHIVE_COUNT" 1
}

@test "process_block: ** в середине первой строки — НЕ жирный заголовок → АРХИВИРОВАТЬ" {
    # grep '^\*\*' требует ** в самом начале
    process_block "Заметка с **bold** словом
Содержимое"

    assert_equal "$KEEP_COUNT" 0
    assert_equal "$ARCHIVE_COUNT" 1
}

@test "process_block: 🔄 в середине первой строки → ОСТАВИТЬ" {
    process_block "Идея 🔄 на потом
Содержимое"

    assert_equal "$KEEP_COUNT" 1
    assert_equal "$ARCHIVE_COUNT" 0
}

# ---------------------------------------------------------------------------
# Интеграционный тест: полный запуск cleanup-processed-notes.sh
# ---------------------------------------------------------------------------

_make_env() {
    # Скрипт ищет FLEETING = $WORKSPACE_DIR/DS-strategy/inbox/fleeting-notes.md
    # Поэтому WORKSPACE_DIR должен быть родителем DS-strategy
    local ws_root="$TEST_DIR/iwe"
    local ws="$ws_root/DS-strategy"
    mkdir -p "$ws/inbox" "$ws/archive/notes"

    # Скрипт вычисляет ENV_FILE = $HOME/.<basename(iwe_ws)>/env
    # iwe_ws = scripts/../../../../ от cleanup-processed-notes.sh
    local script_dir
    script_dir="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
    local iwe_ws
    iwe_ws="$(cd "$script_dir/../../../.." && pwd)"
    local env_dir="$TEST_DIR/.$(basename "$iwe_ws")"
    mkdir -p "$env_dir"
    cat > "$env_dir/env" <<EOF
WORKSPACE_DIR=$ws_root
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
EXOCORTEX_REPO=DS-exocortex
EOF
    echo "$ws"
}

_make_fleeting() {
    local ws="$1"   # это DS-strategy/
    # Файл ДОЛЖЕН содержать frontmatter (---...---) и затем разделитель ---
    # Скрипт ищет: первые два --- = frontmatter, следующий --- = конец заголовка
    cat > "$ws/inbox/fleeting-notes.md" <<'EOF'
---
type: fleeting-notes
---

# Fleeting Notes

> Заметки из Telegram бота и ручного ввода.

---

**Новая идея**
Описание новой идеи которую ещё не обработали

---

Обработанная заметка
Эта заметка уже в Pack, нужно убрать

---

🔄 Идея на ревью
Нужно обдумать позже

---

Ещё одна обработанная
Тоже уже в Pack

---
EOF
}

@test "интеграция: обработанные заметки удаляются из fleeting" {
    local ws
    ws=$(_make_env)
    _make_fleeting "$ws"

    # Переопределяем HOME чтобы скрипт нашёл env
    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_success

    # Обработанные заметки должны исчезнуть
    run grep "Обработанная заметка" "$ws/inbox/fleeting-notes.md"
    assert_failure

    run grep "Ещё одна обработанная" "$ws/inbox/fleeting-notes.md"
    assert_failure
}

@test "интеграция: новые (**) заметки остаются в fleeting" {
    local ws
    ws=$(_make_env)
    _make_fleeting "$ws"

    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_success

    run grep "Новая идея" "$ws/inbox/fleeting-notes.md"
    assert_success
}

@test "интеграция: 🔄 заметки остаются в fleeting" {
    local ws
    ws=$(_make_env)
    _make_fleeting "$ws"

    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_success

    run grep "🔄 Идея на ревью" "$ws/inbox/fleeting-notes.md"
    assert_success
}

@test "интеграция: обработанные заметки попадают в архив" {
    local ws
    ws=$(_make_env)
    _make_fleeting "$ws"

    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_success

    assert_file_exist "$ws/archive/notes/Notes-Archive.md"
    run grep "Обработанная заметка" "$ws/archive/notes/Notes-Archive.md"
    assert_success
}

@test "интеграция: нет fleeting-notes.md → graceful exit" {
    local ws
    ws=$(_make_env)
    # НЕ создаём fleeting-notes.md

    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_success
    assert_output --partial "not found"
}
