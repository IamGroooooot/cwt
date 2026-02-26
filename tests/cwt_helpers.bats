#!/usr/bin/env bats
# Tests for cwt helper functions

setup() {
  load test_helper
  setup
}

teardown() {
  teardown
}

# ── _cwt_relative_time ────────────────────────────────────────────────

@test "_cwt_relative_time: seconds ago returns 'just now'" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    local now=\$(date +%s)
    _cwt_relative_time \$now
  "
  [ "$status" -eq 0 ]
  [ "$output" = "just now" ]
}

@test "_cwt_relative_time: 5 minutes ago returns '5m ago'" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    local now=\$(date +%s)
    local ts=\$(( now - 300 ))
    _cwt_relative_time \$ts
  "
  [ "$status" -eq 0 ]
  [ "$output" = "5m ago" ]
}

@test "_cwt_relative_time: 2 hours ago returns '2h ago'" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    local now=\$(date +%s)
    local ts=\$(( now - 7200 ))
    _cwt_relative_time \$ts
  "
  [ "$status" -eq 0 ]
  [ "$output" = "2h ago" ]
}

@test "_cwt_relative_time: 3 days ago returns '3d ago'" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    local now=\$(date +%s)
    local ts=\$(( now - 259200 ))
    _cwt_relative_time \$ts
  "
  [ "$status" -eq 0 ]
  [ "$output" = "3d ago" ]
}

@test "_cwt_relative_time: 2 weeks ago returns '2w ago'" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    local now=\$(date +%s)
    local ts=\$(( now - 1209600 ))
    _cwt_relative_time \$ts
  "
  [ "$status" -eq 0 ]
  [ "$output" = "2w ago" ]
}

# ── _cwt_require_git ─────────────────────────────────────────────────

@test "_cwt_require_git: fails outside a git repo" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$TEST_TMPDIR'
    _cwt_require_git
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not inside a git repository"* ]]
}

@test "_cwt_require_git: succeeds inside a git repo" {
  create_test_repo
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$REPO_DIR'
    _cwt_require_git
    echo \"exit=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"exit=0"* ]]
}

@test "_cwt_require_git: resolves main repo root from linked worktree" {
  create_test_repo
  git -C "$REPO_DIR" worktree add "$REPO_DIR/wt-linked" -b wt-linked main >/dev/null

  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$REPO_DIR/wt-linked'
    _cwt_require_git
    echo \"git_root=\$_cwt_git_root\"
    echo \"current_root=\$_cwt_current_root\"
  "

  [ "$status" -eq 0 ]
  [[ "$output" == *"git_root=$REPO_DIR"* ]]
  [[ "$output" == *"current_root="* ]]
  [[ "$output" == *"/wt-linked"* ]]
}

@test "_cwt_require_git: default worktree dir is .worktrees" {
  create_test_repo
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$REPO_DIR'
    _cwt_require_git
    echo \"worktrees_dir=\$_cwt_worktrees_dir\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktrees_dir="* ]]
  [[ "$output" == *"/.worktrees"* ]]
}

@test "_cwt_is_valid_assistant: accepts supported assistants" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_is_valid_assistant claude
    echo \"claude=\$?\"
    _cwt_is_valid_assistant codex
    echo \"codex=\$?\"
    _cwt_is_valid_assistant gemini
    echo \"gemini=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude=0"* ]]
  [[ "$output" == *"codex=0"* ]]
  [[ "$output" == *"gemini=0"* ]]
}

@test "_cwt_is_valid_assistant: rejects unknown assistant" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_is_valid_assistant unknown
    echo \"status=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=1"* ]]
}

@test "_cwt_resolve_assistant_cmd: honors command override" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX='echo CODEX'
    source '$CWT_SH'
    _cwt_resolve_assistant_cmd codex
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "echo CODEX" ]]
}

# ── Color functions with NO_COLOR ────────────────────────────────────

@test "color functions strip colors when NO_COLOR=1" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_red 'hello'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "color functions strip colors for _cwt_bold when NO_COLOR=1" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_bold 'world'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "world" ]
}

# ── cwt --version ────────────────────────────────────────────────────

@test "cwt --version prints version" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cwt --version
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "cwt "* ]]
}

# ── cwt --help ───────────────────────────────────────────────────────

@test "cwt --help shows usage information" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cwt --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
}

# ── cwt (unknown command) ───────────────────────────────────────────

@test "cwt with unknown command returns error" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cwt foobar
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}
