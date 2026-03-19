#!/usr/bin/env bats

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'

ROLE_DIR="${BATS_TEST_DIRNAME}/.."
INSTALL_SH="${ROLE_DIR}/install.sh"
ROLE_YAML="${ROLE_DIR}/role.yaml"
PROMPTS_DIR="${ROLE_DIR}/prompts"

@test "install.sh: завершается успешно" {
  run bash "$INSTALL_SH"
  assert_success
}

@test "install.sh: сообщает про /verify usage" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial '/verify [artifact]'
}

@test "install.sh: сообщает про Session Close" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial 'Session Close'
}

@test "role.yaml: name = verifier" {
  run grep '^name: verifier$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: id = R23" {
  run grep '^id: R23$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: auto install = true" {
  run grep '^  auto: true$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: priority = 10" {
  run grep '^  priority: 10$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: active runner отсутствует" {
  run grep '^runner:' "$ROLE_YAML"
  assert_failure
}

@test "prompts: все обязательные файлы существуют" {
  assert_file_exist "$PROMPTS_DIR/verify-content.md"
  assert_file_exist "$PROMPTS_DIR/verify-pack-entity.md"
  assert_file_exist "$PROMPTS_DIR/verify-wp-acceptance.md"
}

@test "prompts: файлы не пустые" {
  run test -s "$PROMPTS_DIR/verify-content.md"
  assert_success
  run test -s "$PROMPTS_DIR/verify-pack-entity.md"
  assert_success
  run test -s "$PROMPTS_DIR/verify-wp-acceptance.md"
  assert_success
}

@test "prompts: начинаются с markdown heading" {
  run bash -c 'head -1 "$0" | grep -q "^# "' "$PROMPTS_DIR/verify-content.md"
  assert_success
  run bash -c 'head -1 "$0" | grep -q "^# "' "$PROMPTS_DIR/verify-pack-entity.md"
  assert_success
  run bash -c 'head -1 "$0" | grep -q "^# "' "$PROMPTS_DIR/verify-wp-acceptance.md"
  assert_success
}
