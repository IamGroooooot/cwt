#!/usr/bin/env bats
# Tests for cwt new

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

@test "cwt new: missing name in non-interactive mode returns guidance" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    echo '' | cwt new
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"required in non-interactive mode"* ]]
  [[ "$output" == *"Usage: cwt new <name>"* ]]
}

@test "cwt new: unknown flag returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --bogus test-wt HEAD
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt new"* ]]
  [[ "$output" == *"cwt new --help"* ]]
}

@test "cwt new: creates worktree with --no-claude" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude test-wt HEAD
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Worktree created"* ]] || [[ "$output" == *"Worktree ready"* ]]
  # Verify the worktree directory exists
  [ -d "$REPO_DIR/.claude/worktrees/test-wt" ]
}

@test "cwt new: duplicate name returns error" {
  # Create first worktree
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude dup-test HEAD
  " 2>/dev/null

  # Try to create again with same name
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude dup-test HEAD
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "cwt new: --no-claude flag skips claude launch" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude skip-claude HEAD
  "
  [ "$status" -eq 0 ]
  # Should show Ready message instead of launching claude
  [[ "$output" == *"Ready"* ]] || [[ "$output" == *"Worktree ready"* ]]
}

@test "cwt new: creates a branch prefixed with wt/" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude branch-test HEAD
  "
  [ "$status" -eq 0 ]
  # Check that a wt/ branch was created
  run git -C "$REPO_DIR" branch --list 'wt/branch-test-*'
  [[ -n "$output" ]]
}

@test "cwt new: explicit branch name is used" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude explicit-wt HEAD feat/my-branch
  "
  [ "$status" -eq 0 ]
  # The branch should exist
  run git -C "$REPO_DIR" rev-parse --verify refs/heads/feat/my-branch
  [ "$status" -eq 0 ]
}

@test "cwt new: non-interactive invocation defaults base branch to HEAD" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-claude no-tty-base < /dev/null
  "
  [ "$status" -eq 0 ]
  [ -d "$REPO_DIR/.claude/worktrees/no-tty-base" ]
}

@test "cwt new --help: shows help" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_new --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"--no-claude"* ]]
}
