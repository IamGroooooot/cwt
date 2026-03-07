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

@test "cwt new: first-run wizard can save the default worktree root" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_SETUP_WIZARD=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    printf '1\n' | cwt new --no-launch wizard-default HEAD
  "

  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/cwt/config" ]
  [[ "$output" == *"No cwt config found"* ]]
  [[ "$output" == *"Saved cwt config"* ]]
  run grep -q "CWT_WORKTREE_DIR" "$XDG_CONFIG_HOME/cwt/config"
  [ "$status" -eq 1 ]
  [ -d "$REPO_DIR/.worktrees/wizard-default" ]
}

@test "cwt new: first-run wizard can create a sibling worktree root" {
  local expected_root
  expected_root="$(cd "$TEST_TMPDIR" && pwd -P)/repo-worktrees"

  run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_SETUP_WIZARD=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    printf '2\n1\n' | cwt new --no-launch wizard-sibling HEAD
  "

  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/cwt/config" ]
  [[ "$output" == *"Worktree root: $expected_root"* ]]
  run grep -q "CWT_WORKTREE_DIR=\\.\\./repo-worktrees" "$XDG_CONFIG_HOME/cwt/config"
  [ "$status" -eq 0 ]
  [ -d "$expected_root/wizard-sibling" ]
}

@test "cwt new: first-run wizard can reuse Claude worktrees" {
  mkdir -p "$REPO_DIR/.claude/worktrees"

  run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_SETUP_WIZARD=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    printf '2\n' | cwt new --no-launch wizard-claude HEAD
  "

  [ "$status" -eq 0 ]
  run grep -q "CWT_WORKTREE_DIR=\\.claude/worktrees" "$XDG_CONFIG_HOME/cwt/config"
  [ "$status" -eq 0 ]
  [ -d "$REPO_DIR/.claude/worktrees/wizard-claude" ]
}

@test "cwt new: first-run wizard can reuse Codex worktrees" {
  mkdir -p "$REPO_DIR/.codex/worktrees"

  run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_SETUP_WIZARD=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    printf '2\n' | cwt new --no-launch wizard-codex HEAD
  "

  [ "$status" -eq 0 ]
  run grep -q "CWT_WORKTREE_DIR=\\.codex/worktrees" "$XDG_CONFIG_HOME/cwt/config"
  [ "$status" -eq 0 ]
  [ -d "$REPO_DIR/.codex/worktrees/wizard-codex" ]
}

@test "cwt new: relative CWT_WORKTREE_DIR in config resolves from git root" {
  mkdir -p "$XDG_CONFIG_HOME/cwt" "$REPO_DIR/apps/api"
  cat > "$XDG_CONFIG_HOME/cwt/config" << 'EOF'
CWT_WORKTREE_DIR=../shared-worktrees
EOF
  local expected_root
  expected_root="$(cd "$TEST_TMPDIR" && pwd -P)/shared-worktrees"

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR/apps/api'
    source '$CWT_SH'
    cwt new --no-launch config-relative HEAD
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using custom worktree root: $expected_root"* ]]
  [ -d "$expected_root/config-relative" ]
  [ ! -d "$REPO_DIR/apps/shared-worktrees/config-relative" ]
}

@test "cwt new: rejects custom worktree dir that resolves to git root" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_WORKTREE_DIR='.'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch unsafe-root HEAD
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be the git root itself"* ]]
}

@test "cwt new: .worktreeinclude copies files and glob matches" {
  mkdir -p "$REPO_DIR/config"
  echo "API_KEY=secret" > "$REPO_DIR/.env"
  echo '{"token":"x"}' > "$REPO_DIR/config/app.secret.json"
  cat > "$REPO_DIR/.worktreeinclude" << 'EOF'
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
  cat > "$REPO_DIR/.worktreeinclude" << 'EOF'
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

@test "cwt new: .worktreeinclude warns and continues for unmatched wildcard" {
  echo "ok" > "$REPO_DIR/keep-wild.txt"
  cat > "$REPO_DIR/.worktreeinclude" << 'EOF'
secrets/*.json
keep-wild.txt
EOF

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch include-wild HEAD
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *".worktreeinclude pattern matched nothing: secrets/*.json"* ]]
  [ -f "$REPO_DIR/.worktrees/include-wild/keep-wild.txt" ]
}

@test "cwt new: .worktreeinclude accepts CRLF and trimmed entries" {
  mkdir -p "$REPO_DIR/config"
  echo "ok" > "$REPO_DIR/.env.local"
  echo '{"trim":"ok"}' > "$REPO_DIR/config/trim.secret.json"
  printf '  # comment\r\n  .env.local  \r\n  config/*.secret.json  \r\n' > "$REPO_DIR/.worktreeinclude"

  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch include-crlf HEAD
  "
  [ "$status" -eq 0 ]
  [ -f "$REPO_DIR/.worktrees/include-crlf/.env.local" ]
  [ -f "$REPO_DIR/.worktrees/include-crlf/config/trim.secret.json" ]
}

@test "cwt new: duplicate name returns error" {
  # Create first worktree
  zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new --no-launch dup-test HEAD
  " 2> /dev/null

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

@test "cwt new: later --no-launch wins over earlier launch flags" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new launch-then-skip HEAD --assistant codex --no-launch
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready"* ]] || [[ "$output" == *"Worktree ready"* ]]
  [[ "$output" != *"Launching codex"* ]]
  [[ "$output" != *"CODEX_OK"* ]]
}

@test "cwt new: invalid permission mode fails when launch is requested" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_PERMISSION_MODE=invalid
    export CWT_CMD_CODEX='echo CODEX_OK'
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new invalid-perm-launch HEAD --assistant codex
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown permission mode"* ]]
}

@test "cwt new: invalid permission mode does not block --no-launch" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_PERMISSION_MODE=invalid
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new invalid-perm-no-launch HEAD --no-launch
  "
  [ "$status" -eq 0 ]
  [ -d "$REPO_DIR/.worktrees/invalid-perm-no-launch" ]
}

@test "cwt new: --all-permissions adds --yolo for codex" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_TEST_CODEX_LOG='$TEST_TMPDIR/codex-new.log'
    mkdir -p '$TEST_TMPDIR/bin'
    cat > '$TEST_TMPDIR/bin/codex' <<'EOF'
#!/usr/bin/env bash
echo \"\$*\" >> \"\${CWT_TEST_CODEX_LOG}\"
exit 0
EOF
    chmod +x '$TEST_TMPDIR/bin/codex'
    export PATH='$TEST_TMPDIR/bin:'\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new full-access-codex HEAD --assistant codex --all-permissions
  "
  [ "$status" -eq 0 ]
  run grep -q -- "--yolo" "$TEST_TMPDIR/codex-new.log"
  [ "$status" -eq 0 ]
}

@test "cwt new: --yolo shortcut launches codex with --yolo" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_TEST_CODEX_LOG='$TEST_TMPDIR/codex-shortcut.log'
    mkdir -p '$TEST_TMPDIR/bin'
    cat > '$TEST_TMPDIR/bin/codex' <<'EOF'
#!/usr/bin/env bash
echo \"\$*\" >> \"\${CWT_TEST_CODEX_LOG}\"
exit 0
EOF
    chmod +x '$TEST_TMPDIR/bin/codex'
    export PATH='$TEST_TMPDIR/bin:'\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new full-access-shortcut HEAD --yolo
  "
  [ "$status" -eq 0 ]
  run grep -q -- "--yolo" "$TEST_TMPDIR/codex-shortcut.log"
  [ "$status" -eq 0 ]
}

@test "cwt new: --dangerously-skip-permissions shortcut launches claude with flag" {
  run zsh -c "
    export NO_COLOR=1
    export CWT_TEST_CLAUDE_LOG='$TEST_TMPDIR/claude-shortcut.log'
    mkdir -p '$TEST_TMPDIR/bin'
    cat > '$TEST_TMPDIR/bin/claude' <<'EOF'
#!/usr/bin/env bash
echo \"\$*\" >> \"\${CWT_TEST_CLAUDE_LOG}\"
exit 0
EOF
    chmod +x '$TEST_TMPDIR/bin/claude'
    export PATH='$TEST_TMPDIR/bin:'\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt new full-access-claude HEAD --dangerously-skip-permissions
  "
  [ "$status" -eq 0 ]
  run grep -q -- "--dangerously-skip-permissions" "$TEST_TMPDIR/claude-shortcut.log"
  [ "$status" -eq 0 ]
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
