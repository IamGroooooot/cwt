#!/usr/bin/env bats
# Tests for cwt ls

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

@test "cwt ls: no worktrees shows helpful message" {
  run_cwt_in "$REPO_DIR" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No worktrees yet"* ]]
}

@test "cwt ls: unknown flag returns error" {
  run_cwt_in "$REPO_DIR" "cwt ls --bogus"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt ls"* ]]
  [[ "$output" == *"cwt ls --help"* ]]
}

@test "cwt ls: lists created worktrees" {
  # Create a worktree first
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch list-test HEAD
  " 2>/dev/null

  run_cwt_in "$REPO_DIR" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"list-test"* ]]
}

@test "cwt ls: works from inside a worktree directory" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch ls-from-wt HEAD
  " 2>/dev/null

  run_cwt_in "$REPO_DIR/.worktrees/ls-from-wt" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ls-from-wt"* ]]
}

@test "cwt ls: shows clean status for unchanged worktree" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch clean-test HEAD
  " 2>/dev/null

  run_cwt_in "$REPO_DIR" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "cwt ls: shows dirty status for modified worktree" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch dirty-test HEAD
  " 2>/dev/null

  # Make the worktree dirty
  echo "modified" > "$REPO_DIR/.worktrees/dirty-test/file.txt"

  run_cwt_in "$REPO_DIR" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty"* ]]
}

@test "cwt ls: lists multiple worktrees" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch wt-alpha HEAD
  " 2>/dev/null

  # Separate zsh invocation so pushd from first cwt new doesn't affect us
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch wt-beta HEAD
  " 2>/dev/null

  run_cwt_in "$REPO_DIR" "cwt ls"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt-alpha"* ]]
  [[ "$output" == *"wt-beta"* ]]
}

@test "cwt ls --help: shows help" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_ls --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}
