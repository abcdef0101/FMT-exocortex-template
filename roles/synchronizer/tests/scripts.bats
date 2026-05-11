#!/usr/bin/env bats

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

SCRIPTS_DIR="${BATS_TEST_DIRNAME}/../scripts"

@test "scheduler.sh: missing required args fails clearly" {
    run bash "$SCRIPTS_DIR/scheduler.sh"
    assert_failure
    assert_output --partial "обязательные параметры не указаны"
}

@test "code-scan.sh: missing required args fails clearly" {
    run bash "$SCRIPTS_DIR/code-scan.sh"
    assert_failure
    assert_output --partial "--workspace-dir"
}

@test "daily-report.sh: missing required args fails clearly" {
    run bash "$SCRIPTS_DIR/daily-report.sh"
    assert_failure
    assert_output --partial "--workspace-dir"
}

@test "dt-collect.sh: missing required args fails clearly" {
    run bash "$SCRIPTS_DIR/dt-collect.sh"
    assert_failure
    assert_output --partial "обязательные параметры не указаны"
}

@test "sync-files.sh: requires at least one target file" {
    local repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo"
    run bash "$SCRIPTS_DIR/sync-files.sh" "$repo"
    assert_failure
    assert_output --partial "хотя бы один файл"
}

@test "code-scan.sh: dry-run reports active downstream repo" {
    local ws="$BATS_TEST_TMPDIR/ws"
    local repo="$ws/DS-app"
    mkdir -p "$repo" "$ws/logs/synchronizer"
    git init --quiet "$repo"
    touch "$ws/test.env"
    echo "hello" > "$repo/file.txt"
    git -C "$repo" add file.txt
    git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "seed" --quiet

    run bash "$SCRIPTS_DIR/code-scan.sh" --workspace-dir "$ws" --env-file "$ws/test.env" --dry-run
    assert_success
    assert_output --partial "FOUND: DS-app"
    assert_output --partial "Итого: 1 репо, 1 коммит"
}

@test "video-scan.sh: matches WP id and transcript" {
    local ws="$BATS_TEST_TMPDIR/ws"
    local videos="$BATS_TEST_TMPDIR/videos"
    mkdir -p "$ws/memory" "$ws/logs/synchronizer" "$videos/transcripts"
    touch "$videos/recording-WP-42-2026-05-10.mp4"
    touch "$videos/transcripts/recording-WP-42-2026-05-10.txt"
    cat > "$ws/memory/day-rhythm-config.yaml" <<EOF
video:
  enabled: true
  stale_days: 3
  transcripts_dir: transcripts
  directories:
    - "$videos"
  extensions: [mp4]
EOF

    run bash "$SCRIPTS_DIR/video-scan.sh" --workspace-dir "$ws" --dry-run
    assert_success
    assert_output --partial "WP-42"
    assert_output --partial "recording-WP-42-2026-05-10.mp4"
}
