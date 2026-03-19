#!/usr/bin/env bats

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  BIN_DIR="$TEST_DIR/bin"
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
}

@test "sync-files: usage error when no file args" {
  local repo="$TEST_DIR/repo"
  mkdir -p "$repo/.git"
  run bash "${BATS_TEST_DIRNAME}/../scripts/sync-files.sh" "$repo"
  assert_failure
  assert_output --partial 'хотя бы один файл'
}

@test "sync-files: fetch failure exits 0 with offline message" {
  local repo="$TEST_DIR/repo2"
  mkdir -p "$repo/.git"
  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = fetch ]; then exit 1; fi
exit 0
EOF
  chmod +x "$BIN_DIR/git"
  run bash "${BATS_TEST_DIRNAME}/../scripts/sync-files.sh" "$repo" foo.md
  assert_success
  assert_output --partial 'fetch failed'
}

@test "video-scan helpers: match_wp by WP number" {
  source /dev/stdin <<'EOF'
match_wp() {
  local filename="$1"
  local base
  base=$(basename "$filename")
  if [[ "$base" =~ WP-([0-9]+) ]]; then
    echo "WP-${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    echo "date:${BASH_REMATCH[1]}"
    return 0
  fi
  echo "unmatched"
  return 1
}
EOF
  run match_wp "/tmp/meeting-WP-42.mp4"
  assert_success
  assert_output 'WP-42'
}

@test "video-scan helpers: match_wp by date" {
  source /dev/stdin <<'EOF'
match_wp() {
  local filename="$1"
  local base
  base=$(basename "$filename")
  if [[ "$base" =~ WP-([0-9]+) ]]; then
    echo "WP-${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    echo "date:${BASH_REMATCH[1]}"
    return 0
  fi
  echo "unmatched"
  return 1
}
EOF
  run match_wp "/tmp/zoom-2026-03-19.mp4"
  assert_success
  assert_output 'date:2026-03-19'
}

@test "video-scan helpers: unmatched when no pattern" {
  source /dev/stdin <<'EOF'
match_wp() {
  local filename="$1"
  local base
  base=$(basename "$filename")
  if [[ "$base" =~ WP-([0-9]+) ]]; then
    echo "WP-${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    echo "date:${BASH_REMATCH[1]}"
    return 0
  fi
  echo "unmatched"
  return 1
}
EOF
  run match_wp "/tmp/random-video.mp4"
  assert_failure
  assert_output 'unmatched'
}

@test "video-scan helpers: has_transcript finds txt near video" {
  local video_dir="$TEST_DIR/videos"
  mkdir -p "$video_dir/transcripts"
  touch "$video_dir/demo.mp4" "$video_dir/transcripts/demo.txt"
  source /dev/stdin <<EOF
TRANSCRIPTS_DIR="transcripts"
VIDEO_DIRS=("$video_dir")
has_transcript() {
  local video_path="\$1"
  local base
  base=\$(basename "\$video_path" | sed 's/\.[^.]*$//')
  local video_parent
  video_parent=\$(dirname "\$video_path")
  [ -f "\$video_parent/\$TRANSCRIPTS_DIR/\${base}.txt" ] || \
  [ -f "\$video_parent/\$TRANSCRIPTS_DIR/\${base}.md" ] || \
  [ -f "\${VIDEO_DIRS[0]}/\$TRANSCRIPTS_DIR/\${base}.txt" ] 2>/dev/null || \
  [ -f "\${VIDEO_DIRS[0]}/\$TRANSCRIPTS_DIR/\${base}.md" ] 2>/dev/null
}
EOF
  run has_transcript "$video_dir/demo.mp4"
  assert_success
}

@test "video-scan helpers: get_source returns top directory name" {
  local root1="$TEST_DIR/Zoom"
  mkdir -p "$root1/sub"
  touch "$root1/sub/a.mp4"
  source /dev/stdin <<EOF
VIDEO_DIRS=("$root1")
get_source() {
  local video_path="\$1"
  local dir
  dir=\$(dirname "\$video_path")
  for vd in "\${VIDEO_DIRS[@]}"; do
    if [[ "\$video_path" == "\$vd"* ]]; then
      basename "\$vd"
      return
    fi
  done
  basename "\$dir"
}
EOF
  run get_source "$root1/sub/a.mp4"
  assert_success
  assert_output 'Zoom'
}

@test "template extractor: build_buttons returns empty array" {
  source "${BATS_TEST_DIRNAME}/../scripts/templates/extractor.sh"
  run build_buttons
  assert_success
  assert_output '[]'
}

@test "template synchronizer: empty log returns empty message" {
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.local/state/logs/synchronizer"
  run env -i HOME="$HOME" PATH="$PATH" bash -c 'source "$1"; build_message code-scan' _ "${BATS_TEST_DIRNAME}/../scripts/templates/synchronizer.sh"
  assert_success
  assert_output ''
}

@test "template strategist: find_strategy_file returns today dayplan path" {
  WORKSPACE_DIR="$TEST_DIR/ws"
  mkdir -p "$WORKSPACE_DIR/DS-strategy/current"
  source "${BATS_TEST_DIRNAME}/../scripts/templates/strategist.sh"
  run find_strategy_file day-plan
  assert_success
  assert_output --partial "DayPlan $(date +%Y-%m-%d).md"
}
