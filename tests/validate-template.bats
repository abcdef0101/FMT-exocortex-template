#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'test_helper/validate_helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../setup/validate-template.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR/template"
  make_valid_template_fixture "$TEST_DIR"
}

@test "validate-template: PASS на валидном шаблоне" {
  run bash "$SCRIPT" "$TEST_DIR"
  assert_success
  assert_output --partial 'ALL CHECKS PASSED'
}

@test "validate-template: FAIL на author-specific content" {
  echo 'tserentserenov local text' >> "$TEST_DIR/README.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'Author-specific content... FAIL'
}

@test "validate-template: github URL с author-specific token не считается ошибкой" {
  echo 'https://github.com/TserenTserenov/FMT-exocortex-template' >> "$TEST_DIR/README.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_success
}

@test "validate-template: FAIL на hardcoded /Users/ path" {
  echo '/Users/alice/project' >> "$TEST_DIR/README.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'Hardcoded /Users/ paths... FAIL'
}

@test "validate-template: FAIL на hardcoded /opt/homebrew path" {
  echo '/opt/homebrew/bin/python3' >> "$TEST_DIR/memory/navigation.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'Hardcoded /opt/homebrew paths... FAIL'
}

@test "validate-template: README с /opt/homebrew допускается" {
  echo '/opt/homebrew/bin/brew' >> "$TEST_DIR/README.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_success
}

@test "validate-template: FAIL если MEMORY.md не skeleton" {
  for i in $(seq 1 20); do echo "| $i | rp | 1h | P1 | pending | — |" >> "$TEST_DIR/memory/MEMORY.md"; done
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'MEMORY.md is skeleton... FAIL'
}

@test "validate-template: FAIL если отсутствует обязательный файл" {
  rm "$TEST_DIR/ONTOLOGY.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'MISSING: ONTOLOGY.md'
}

@test "validate-template: WARN если отсутствует MEMORY.md" {
  rm "$TEST_DIR/memory/MEMORY.md"
  run bash "$SCRIPT" "$TEST_DIR"
  assert_failure
  assert_output --partial 'MEMORY.md is skeleton... WARN'
}
