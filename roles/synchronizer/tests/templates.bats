#!/usr/bin/env bats
# Тесты для templates/ шаблонов уведомлений (ADR-014)

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

setup() {
    WORKSPACE_DIR="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$WORKSPACE_DIR/DS-strategy/current" \
        "$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports" \
        "$WORKSPACE_DIR/logs/extractor" \
        "$WORKSPACE_DIR/logs/synchronizer"
    export WORKSPACE_DIR
    export DATE=$(date +%Y-%m-%d)
}

# ===========================================================================
# strategist.sh
# ===========================================================================

STRATEGIST_TPL="${BATS_TEST_DIRNAME}/../../strategist/scripts/templates/strategist.sh"

@test "template/strategist: build_message day-plan" {
    local dayplan="$WORKSPACE_DIR/DS-strategy/current/DayPlan $DATE.md"
    printf '# Day Plan\n\n## План на сегодня\n| # | РП | Бюджет | Приоритет | Статус |\n|---|---|---|---|---|\n| 1 | Тестовый РП | 2h | P1 | ✅ done |\n' > "$dayplan"

    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "day-plan"
    assert_success
    assert_output --partial "План"
}

@test "template/strategist: build_message note-review" {
    local dayplan="$WORKSPACE_DIR/DS-strategy/current/DayPlan $DATE.md"
    touch "$dayplan"
    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "note-review"
    assert_success
    assert_output --partial "Note-Review"
}

@test "template/strategist: build_message неизвестный сценарий" {
    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "nonexistent"
    assert_success
    [ -z "$output" ]
}

# ===========================================================================
# extractor.sh
# ===========================================================================

EXTRACTOR_TPL="${BATS_TEST_DIRNAME}/../../extractor/scripts/templates/extractor.sh"

@test "template/extractor: build_message inbox-check без отчёта" {
    run bash -c 'source "$1"; build_message "$2"' _ "$EXTRACTOR_TPL" "inbox-check"
    assert_success
    [ -z "$output" ]
}

@test "template/extractor: build_message inbox-check с отчётом" {
    local report="$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports/${DATE}-test.md"
    printf '## Кандидат 1\nВердикт: accept\n\n## Кандидат 2\nВердикт: accept\n' > "$report"

    run bash -c 'source "$1"; build_message "$2"' _ "$EXTRACTOR_TPL" "inbox-check"
    assert_success
    assert_output --partial "Knowledge Extractor"
    assert_output --partial "Кандидатов: 2"
}

@test "template/extractor: build_message audit" {
    run bash -c 'source "$1"; build_message "$2"' _ "$EXTRACTOR_TPL" "audit"
    assert_success
    assert_output --partial "Knowledge Audit"
}

# ===========================================================================
# synchronizer.sh
# ===========================================================================

SYNC_TPL="${BATS_TEST_DIRNAME}/../../synchronizer/scripts/templates/synchronizer.sh"

@test "template/synchronizer: build_message code-scan без лога" {
    run bash -c 'source "$1"; build_message "$2"' _ "$SYNC_TPL" "code-scan"
    assert_success
    [ -z "$output" ]
}

@test "template/synchronizer: build_message code-scan с логом" {
    local log="$WORKSPACE_DIR/logs/synchronizer/code-scan-$DATE.log"
    printf '=== Code Scan Started ===\n2026-05-11 00:00\nFOUND: repo1 (+5 commits)\nFOUND: repo2 (+2 commits)\nSKIP: repo3\n=== Code Scan Completed ===\n' > "$log"

    run bash -c 'source "$1"; build_message "$2"' _ "$SYNC_TPL" "code-scan"
    assert_success
    assert_output --partial "Code Scan"
    assert_output --partial "Репо с коммитами: 2"
}

@test "template/synchronizer: build_message dt-collect успех" {
    local log="$WORKSPACE_DIR/logs/synchronizer/dt-collect-$DATE.log"
    echo 'DT Collect Completed Successfully' > "$log"

    run bash -c 'source "$1"; build_message "$2"' _ "$SYNC_TPL" "dt-collect"
    assert_success
    assert_output --partial "DT Collect"
}

# ===========================================================================
# verifier.sh
# ===========================================================================

VERIFIER_TPL="${BATS_TEST_DIRNAME}/../../verifier/scripts/templates/verifier.sh"

@test "template/verifier: build_message verify-pack-entity" {
    run bash -c 'source "$1"; build_message "$2"' _ "$VERIFIER_TPL" "verify-pack-entity"
    assert_success
    assert_output --partial "Верификация Pack Entity"
}

@test "template/verifier: build_message verify-content" {
    run bash -c 'source "$1"; build_message "$2"' _ "$VERIFIER_TPL" "verify-content"
    assert_success
    assert_output --partial "Верификация контента"
}

@test "template/verifier: build_message on-demand" {
    run bash -c 'source "$1"; build_message "$2"' _ "$VERIFIER_TPL" "on-demand"
    assert_success
    assert_output --partial "On-demand"
}

# ===========================================================================
# auditor.sh
# ===========================================================================

AUDITOR_TPL="${BATS_TEST_DIRNAME}/../../auditor/scripts/templates/auditor.sh"

@test "template/auditor: build_message audit-plan-consistency" {
    run bash -c 'source "$1"; build_message "$2"' _ "$AUDITOR_TPL" "audit-plan-consistency"
    assert_success
    assert_output --partial "Аудит планов"
}

@test "template/auditor: build_message audit-coverage" {
    run bash -c 'source "$1"; build_message "$2"' _ "$AUDITOR_TPL" "audit-coverage"
    assert_success
    assert_output --partial "Аудит покрытия"
}

@test "template/auditor: build_message on-demand" {
    run bash -c 'source "$1"; build_message "$2"' _ "$AUDITOR_TPL" "on-demand"
    assert_success
    assert_output --partial "On-demand"
}

# ===========================================================================
# Недостающие сценарии (ADR-014 gaps)
# ===========================================================================

@test "template/strategist: build_message session-prep" {
    local weekplan="$WORKSPACE_DIR/DS-strategy/current/WeekPlan W22.md"
    printf '# WeekPlan W22\n\n## Рабочие продукты\n| # | РП | Бюджет | Приоритет | Статус |\n|---|---|---|---|---|\n| 1 | План | 3h | P1 | ✅ done |\n' > "$weekplan"

    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "session-prep"
    assert_success
    assert_output --partial "Рабочие продукты"
}

@test "template/strategist: build_message week-review" {
    local weekplan="$WORKSPACE_DIR/DS-strategy/current/WeekPlan W22.md"
    printf '# WeekPlan W22 — Итоги недели\n' > "$weekplan"

    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "week-review"
    assert_success
    assert_output --partial "WeekPlan W22"
}

@test "template/strategist: build_message evening" {
    local dayplan="$WORKSPACE_DIR/DS-strategy/current/DayPlan $DATE.md"
    printf '# Evening Review\n\n## План на сегодня\n| # | РП | Бюджет | Приоритет | Статус |\n|---|---|---|---|---|\n| 1 | РП1 | 1h | P2 | ✅ done |\n' > "$dayplan"

    run bash -c 'source "$1"; build_message "$2"' _ "$STRATEGIST_TPL" "evening"
    assert_success
    assert_output --partial "evening"
}

@test "template/synchronizer: build_message dt-collect ошибка" {
    local log="$WORKSPACE_DIR/logs/synchronizer/dt-collect-$DATE.log"
    echo 'DT Collect FAILED: database unreachable' > "$log"

    run bash -c 'source "$1"; build_message "$2"' _ "$SYNC_TPL" "dt-collect"
    assert_success
    assert_output --partial "Ошибка"
}

@test "template/synchronizer: build_message code-scan без коммитов" {
    local log="$WORKSPACE_DIR/logs/synchronizer/code-scan-$DATE.log"
    printf '=== Code Scan Started ===\nSKIP: repo1\nSKIP: repo2\n=== Code Scan Completed ===\n' > "$log"

    run bash -c 'source "$1"; build_message "$2"' _ "$SYNC_TPL" "code-scan"
    assert_success
    assert_output --partial "Репо с коммитами: 0"
}

@test "template/verifier: build_message verify-wp-acceptance" {
    run bash -c 'source "$1"; build_message "$2"' _ "$VERIFIER_TPL" "verify-wp-acceptance"
    assert_success
    assert_output --partial "приёмки"
}
