#!/usr/bin/env bats
# Tests for cwt update

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

@test "cwt update: unknown flag returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt update --bogus
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt update"* ]]
  [[ "$output" == *"cwt update --help"* ]]
}
