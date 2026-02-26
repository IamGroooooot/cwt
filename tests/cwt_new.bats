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

@test "cwt new: creates worktree with --no-launch" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch test-wt HEAD
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Worktree created"* ]] || [[ "$output" == *"Worktree ready"* ]]
  # Verify the worktree directory exists
  [ -d "$REPO_DIR/.worktrees/test-wt" ]
}

@test "cwt new: adds .worktrees/ to .gitignore when missing" {
  rm -f "$REPO_DIR/.gitignore"

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch ignore-check HEAD
  "
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.gitignore" ]
  run grep -E '^[[:space:]]*\.worktrees/?[[:space:]]*$' "$REPO_DIR/.gitignore"
  [ "$status" -eq 0 ]
}

@test "cwt new: .worktreeinclude copies files and glob matches" {
  mkdir -p "$REPO_DIR/config"
  echo "API_KEY=secret" > "$REPO_DIR/.env"
  echo '{"token":"x"}' > "$REPO_DIR/config/app.secret.json"
  cat > "$REPO_DIR/.worktreeinclude" <<'EOF'
# secrets
.env
config/*.secret.json
EOF

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch include-copy HEAD
  "
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.worktrees/include-copy/.env" ]
  [ -f "$REPO_DIR/.worktrees/include-copy/config/app.secret.json" ]
}

@test "cwt new: .worktreeinclude ignores comments and missing patterns" {
  echo "hello" > "$REPO_DIR/keep.txt"
  cat > "$REPO_DIR/.worktreeinclude" <<'EOF'
# comment line

missing.file
keep.txt
EOF

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch include-ignore HEAD
  "
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.worktrees/include-ignore/keep.txt" ]
  [ ! -e "$REPO_DIR/.worktrees/include-ignore/missing.file" ]
}

@test "cwt new: duplicate name returns error" {
  # Create first worktree
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch dup-test HEAD
  " 2>/dev/null

  # Try to create again with same name
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch dup-test HEAD
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "cwt new: --no-launch flag skips assistant launch" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch skip-claude HEAD
  "
  [ "$status" -eq 0 ]
  # Should show Ready message instead of launching an assistant
  [[ "$output" == *"Ready"* ]] || [[ "$output" == *"Worktree ready"* ]]
}

@test "cwt new: launches selected assistant with --assistant" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new launch-codex HEAD --assistant codex
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Launching codex"* ]]
  [[ "$output" == *"CODEX_OK"* ]]
}

@test "cwt new: explicit assistant launch overrides CWT_AUTO_LAUNCH=false" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_AUTO_LAUNCH=false
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new launch-override HEAD --assistant codex
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Launching codex"* ]]
  [[ "$output" == *"CODEX_OK"* ]]
}

@test "cwt new: explicit --split fails outside tmux/zellij" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new split-no-mux HEAD --assistant codex --split
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires tmux or zellij"* ]]
}

@test "cwt new: config launch target falls back to current shell when no mux" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_LAUNCH_TARGET=split
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new split-fallback HEAD --assistant codex
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tmux/zellij session detected"* ]]
  [[ "$output" == *"CODEX_OK"* ]]
}

@test "cwt new: --split launches in tmux pane when inside tmux" {
  run zsh -c "
    export NO_COLOR=1
    export TMUX='test-session'
    export CWT_TEST_TMUX_LOG='$TEST_TMPDIR/tmux.log'
    export CWT_CMD_CODEX='echo CODEX_OK'
    mkdir -p '$TEST_TMPDIR/bin'
    cat > '$TEST_TMPDIR/bin/tmux' <<'EOF'
#!/usr/bin/env bash
echo \"\$*\" >> \"\${CWT_TEST_TMUX_LOG}\"
exit 0
EOF
    chmod +x '$TEST_TMPDIR/bin/tmux'
    export PATH='$TEST_TMPDIR/bin:'\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new split-tmux HEAD --assistant codex --split
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opened codex in tmux split"* ]]
  run grep -q "split-window" "$TEST_TMPDIR/tmux.log"
  [ "$status" -eq 0 ]
}

@test "cwt new: --split launches in zellij pane when inside zellij" {
  run zsh -c "
    export NO_COLOR=1
    export ZELLIJ='test-session'
    export CWT_TEST_ZELLIJ_LOG='$TEST_TMPDIR/zellij.log'
    export CWT_CMD_CODEX='echo CODEX_OK'
    mkdir -p '$TEST_TMPDIR/bin'
    cat > '$TEST_TMPDIR/bin/zellij' <<'EOF'
#!/usr/bin/env bash
echo \"\$*\" >> \"\${CWT_TEST_ZELLIJ_LOG}\"
exit 0
EOF
    chmod +x '$TEST_TMPDIR/bin/zellij'
    export PATH='$TEST_TMPDIR/bin:'\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new split-zellij HEAD --assistant codex --split
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opened codex in zellij split"* ]]
  run grep -q "action new-pane -d right --cwd" "$TEST_TMPDIR/zellij.log"
  [ "$status" -eq 0 ]
}

@test "cwt new: assistant launch failure returns non-zero" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX=false
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new launch-fail HEAD --assistant codex
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Assistant 'codex' exited with code"* ]]
}

@test "cwt new: missing assistant command returns error" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_GEMINI='definitely-missing-command'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new missing-cmd HEAD --assistant gemini
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Selected assistant 'gemini' is not available"* ]]
}

@test "cwt new: unknown assistant returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new unknown-assistant HEAD --assistant no-such-assistant
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown assistant"* ]]
}

@test "cwt new: creates a branch prefixed with wt/" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch branch-test HEAD
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
    cwt new --no-launch explicit-wt HEAD feat/my-branch
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
    cwt new --no-launch no-tty-base < /dev/null
  "
  [ "$status" -eq 0 ]
  [ -d "$REPO_DIR/.worktrees/no-tty-base" ]
}

@test "cwt new --help: shows help" {
  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_new --help
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"--assistant"* ]]
  [[ "$output" == *"--launch-target"* ]]
  [[ "$output" == *"--current"* ]]
  [[ "$output" == *"--split"* ]]
  [[ "$output" == *"--no-launch"* ]]
}
