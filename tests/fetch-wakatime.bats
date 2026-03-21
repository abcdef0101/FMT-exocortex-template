#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_DIR="$TEST_DIR/workspace"
  EXO_DIR="$WORKSPACE_DIR/FMT-exocortex-template"
  BIN_DIR="$TEST_DIR/bin"
  export HOME="$HOME_DIR"

  mkdir -p "$HOME_DIR/.config/aist" "$BIN_DIR" "$EXO_DIR/roles/strategist/scripts" "$EXO_DIR/roles/strategist/lib" "$EXO_DIR/lib"
  cp "${BATS_TEST_DIRNAME}/../roles/strategist/scripts/fetch-wakatime.sh" "$EXO_DIR/roles/strategist/scripts/fetch-wakatime.sh"
  cp -R "${BATS_TEST_DIRNAME}/../roles/strategist/lib/." "$EXO_DIR/roles/strategist/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"

  cat > "$HOME_DIR/.config/aist/env" <<'EOF'
WAKATIME_API_KEY=test-key
EOF

  export PATH="$BIN_DIR:$PATH"

  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%u) printf '%s\n' '3' ;;
  +%Y-%m-%d) printf '%s\n' '2026-03-21' ;;
  *) /bin/date "$@" ;;
esac
EOF
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"cumulative_total":{"text":"1 hr"},"data":[{"projects":[{"name":"demo","text":"1 hr","total_seconds":3600}],"languages":[{"name":"Bash","text":"1 hr","total_seconds":3600}]}]}'
EOF
  chmod +x "$BIN_DIR/date" "$BIN_DIR/curl" "$EXO_DIR/roles/strategist/scripts/fetch-wakatime.sh"
}

@test "fetch-wakatime day: renders daily markdown" {
  run bash "$EXO_DIR/roles/strategist/scripts/fetch-wakatime.sh" day

  assert_success
  assert_output --partial '## WakaTime: вчера'
  assert_output --partial '| demo | 1 hr |'
}

@test "fetch-wakatime week: renders weekly markdown" {
  run bash "$EXO_DIR/roles/strategist/scripts/fetch-wakatime.sh" week

  assert_success
  assert_output --partial '## WakaTime: статистика рабочего времени'
  assert_output --partial '### Текущая неделя'
  assert_output --partial '### Предыдущая неделя'
}
