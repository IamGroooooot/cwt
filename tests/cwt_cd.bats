#!/usr/bin/env bats
# Tests for cwt cd

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

@test "cwt cd: non-existent worktree returns error" {
  # Create the worktrees dir so cwt cd doesn't bail early
  mkdir -p "$REPO_DIR/.worktrees"

  # Create at least one worktree so there's something to list
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch some-wt HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd nonexistent
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not found"* ]]
}

@test "cwt cd: unknown flag returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd --bogus
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt cd"* ]]
  [[ "$output" == *"cwt cd --help"* ]]
}

@test "cwt cd: enters valid worktree directory" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch cd-test HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd cd-test
    pwd
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *".worktrees/cd-test"* ]]
}

@test "cwt cd: shows success message" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch msg-test HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd msg-test
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Entered"* ]]
  [[ "$output" == *"msg-test"* ]]
}

@test "cwt cd: launches selected assistant with --assistant" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch launch-test HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd launch-test --assistant codex
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Launching codex"* ]]
  [[ "$output" == *"CODEX_OK"* ]]
}

@test "cwt cd: unknown assistant returns error" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch bad-assistant HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd bad-assistant --assistant unknown
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown assistant"* ]]
}

@test "cwt cd: from inside worktree without name enters main repo" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch home-wt HEAD
  " 2>/dev/null

  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch other-wt HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR/.worktrees/home-wt'
    source '$CWT_SH'
    cwt cd
    pwd
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Entered main repository"* ]]
  [[ "$output" == *"$REPO_DIR"* ]]
  [[ "$output" == *"other-wt"* ]]
}

@test "cwt cd: no worktrees shows helpful message" {
  run_cwt_in "$REPO_DIR" "cwt cd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No worktrees yet"* ]] || [[ "$output" == *"cwt new"* ]]
}

@test "cwt cd: non-interactive without name returns guidance" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch no-tty-cd HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt cd < /dev/null
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"required in non-interactive mode"* ]]
  [[ "$output" == *"Usage: cwt cd <name> [--assistant <assistant>"* ]]
}

@test "cwt cd --help: shows help" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_cd --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"--assistant"* ]]
  [[ "$output" == *"--codex"* ]]
  [[ "$output" == *"--claude"* ]]
}
