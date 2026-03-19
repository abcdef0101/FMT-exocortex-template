#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

ROOT="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME="$TEST_DIR/home"
  BIN_DIR="$TEST_DIR/bin"
  CALLS="$TEST_DIR/calls.log"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.config/systemd/user" "$BIN_DIR"
  export HOME CALLS
  cat > "$BIN_DIR/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$CALLS"
exit 0
EOF
  cat > "$BIN_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
exit 0
EOF
  chmod +x "$BIN_DIR/launchctl" "$BIN_DIR/systemctl"
  export PATH="$BIN_DIR:$PATH"
}

@test "strategist install: linux installs systemd timers" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=linux-gnu bash "$ROOT/roles/strategist/install.sh"
  assert_success
  assert_file_exist "$HOME/.config/systemd/user/exocortex-strategist-morning.service"
  assert_file_exist "$HOME/.config/systemd/user/exocortex-strategist-morning.timer"
  assert_file_exist "$HOME/.config/systemd/user/exocortex-strategist-weekreview.service"
  assert_file_exist "$HOME/.config/systemd/user/exocortex-strategist-weekreview.timer"
}

@test "strategist install: macOS installs launchd plists" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=darwin bash "$ROOT/roles/strategist/install.sh"
  assert_success
  assert_file_exist "$HOME/Library/LaunchAgents/com.strategist.morning.plist"
  assert_file_exist "$HOME/Library/LaunchAgents/com.strategist.weekreview.plist"
  run grep 'launchctl load' "$CALLS"
  assert_success
}

@test "extractor install: linux installs systemd timer" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=linux-gnu bash "$ROOT/roles/extractor/install.sh"
  assert_success
  assert_file_exist "$HOME/.config/systemd/user/exocortex-extractor.service"
  assert_file_exist "$HOME/.config/systemd/user/exocortex-extractor.timer"
  assert_output --partial 'every 3h'
}

@test "extractor install: macOS installs launchd plist" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=darwin bash "$ROOT/roles/extractor/install.sh"
  assert_success
  assert_file_exist "$HOME/Library/LaunchAgents/com.extractor.inbox-check.plist"
  run grep 'launchctl load' "$CALLS"
  assert_success
}

@test "synchronizer install: linux installs scheduler timer" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=linux-gnu bash "$ROOT/roles/synchronizer/install.sh"
  assert_success
  assert_file_exist "$HOME/.config/systemd/user/exocortex-scheduler.service"
  assert_file_exist "$HOME/.config/systemd/user/exocortex-scheduler.timer"
  assert_dir_exist "$HOME/.local/state/exocortex"
  assert_dir_exist "$HOME/.local/state/logs/synchronizer"
}

@test "synchronizer install: macOS installs scheduler plist" {
  run env HOME="$HOME" PATH="$PATH" OSTYPE=darwin bash "$ROOT/roles/synchronizer/install.sh"
  assert_success
  assert_file_exist "$HOME/Library/LaunchAgents/com.exocortex.scheduler.plist"
  assert_output --partial 'com.exocortex.scheduler'
}
