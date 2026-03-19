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

@test "install.sh: сообщает что роль on-demand" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial 'on-demand'
}

@test "install.sh: печатает путь к prompts" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial 'Prompts:'
}

@test "install.sh: упоминает Day Open" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial 'Day Open'
}

@test "install.sh: упоминает strategy session" {
  run bash "$INSTALL_SH"
  assert_success
  assert_output --partial 'Strategy session'
}

@test "role.yaml: существует" {
  assert_file_exist "$ROLE_YAML"
}

@test "role.yaml: name = auditor" {
  run grep '^name: auditor$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: id = R24" {
  run grep '^id: R24$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: auto install = true" {
  run grep '^  auto: true$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: priority = 11" {
  run grep '^  priority: 11$' "$ROLE_YAML"
  assert_success
}

@test "role.yaml: runner отсутствует как активное поле" {
  run grep '^runner:' "$ROLE_YAML"
  assert_failure
}

@test "role.yaml: есть комментарий про отсутствие runner" {
  run grep 'Нет runner' "$ROLE_YAML"
  assert_success
}

@test "prompts/: директория существует" {
  assert_dir_exist "$PROMPTS_DIR"
}

@test "prompts/: содержит audit-coverage.md" {
  assert_file_exist "$PROMPTS_DIR/audit-coverage.md"
}

@test "prompts/: содержит audit-plan-consistency.md" {
  assert_file_exist "$PROMPTS_DIR/audit-plan-consistency.md"
}

@test "audit-coverage.md: файл не пустой" {
  run test -s "$PROMPTS_DIR/audit-coverage.md"
  assert_success
}

@test "audit-plan-consistency.md: файл не пустой" {
  run test -s "$PROMPTS_DIR/audit-plan-consistency.md"
  assert_success
}

@test "prompts: оба markdown-файла начинаются с заголовка" {
  run bash -c 'head -1 "$0" | grep -q "^# "' "$PROMPTS_DIR/audit-coverage.md"
  assert_success
  run bash -c 'head -1 "$0" | grep -q "^# "' "$PROMPTS_DIR/audit-plan-consistency.md"
  assert_success
}
