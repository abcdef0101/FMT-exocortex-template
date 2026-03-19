#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "локальные markdown-ссылки во всём проекте валидны" {
  run python3 "${BATS_TEST_DIRNAME}/validate_markdown_links.py"
  assert_success
  assert_output --partial "All local markdown links are valid."
}
