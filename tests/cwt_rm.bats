#!/usr/bin/env bats
# Tests for cwt rm

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

@test "cwt rm: non-existent worktree returns error" {
  # Need at least one worktree to get past the "no worktrees" check
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch existing-wt HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm nonexistent
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"Not found"* ]] || [[ "$output" == *"Worktree not found"* ]]
}

@test "cwt rm: unknown flag returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm --bogus
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt rm"* ]]
  [[ "$output" == *"cwt rm --help"* ]]
}

@test "cwt rm: force flag removes worktree without prompting" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch rm-force HEAD
  " 2>/dev/null

  [ -d "$REPO_DIR/.worktrees/rm-force" ]

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm -f rm-force
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"* ]] || [[ "$output" == *"Removed"* ]]
  # Worktree directory should be gone
  [ ! -d "$REPO_DIR/.worktrees/rm-force" ]
}

@test "cwt rm: removes the associated branch" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch rm-branch HEAD feat/rm-test
  " 2>/dev/null

  # Verify branch exists
  run git -C "$REPO_DIR" rev-parse --verify refs/heads/feat/rm-test
  [ "$status" -eq 0 ]

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm -f rm-branch
  "
  [ "$status" -eq 0 ]

  # Branch should be deleted
  run git -C "$REPO_DIR" rev-parse --verify refs/heads/feat/rm-test
  [ "$status" -ne 0 ]
}

@test "cwt rm: named remove without worktrees returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm something
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No worktrees found"* ]]
  [[ "$output" == *"something"* ]]
}

@test "cwt rm: no name without worktrees shows informative message" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"No worktrees to remove"* ]]
}

@test "cwt rm: non-interactive without name returns guidance" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch rm-noninteractive HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm < /dev/null
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"required in non-interactive mode"* ]]
  [[ "$output" == *"Usage: cwt rm <name> [-f|--force]"* ]]
}

@test "cwt rm: non-interactive named remove requires --force" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch rm-confirm HEAD
  " 2>/dev/null

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt rm rm-confirm < /dev/null
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Confirmation required in non-interactive mode"* ]]
  [[ "$output" == *"--force"* ]]
  [ -d "$REPO_DIR/.worktrees/rm-confirm" ]
}

@test "cwt rm: can remove current worktree and return to main repo" {
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch rm-current HEAD
  " 2>/dev/null

  [ -d "$REPO_DIR/.worktrees/rm-current" ]

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR/.worktrees/rm-current'
    source '$CWT_SH'
    cwt rm -f rm-current
    pwd
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Moved to main repository"* ]]
  [[ "$output" == *"$REPO_DIR"* ]]
  [ ! -d "$REPO_DIR/.worktrees/rm-current" ]
}

@test "cwt rm --help: shows help" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_rm --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"--force"* ]]
}
