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

@test "_cwt_relative_path_from: returns sibling path" {
	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_relative_path_from /tmp/project /tmp/project-worktrees
  "
	[ "$status" -eq 0 ]
	[ "$output" = "../project-worktrees" ]
}

@test "_cwt_print_detected_worktree_roots: lists Claude and Codex roots when present" {
	create_test_repo
	mkdir -p "$REPO_DIR/.claude/worktrees" "$REPO_DIR/.codex/worktrees"

	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$REPO_DIR'
    _cwt_require_git
    _cwt_print_detected_worktree_roots
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Reuse existing Claude worktrees|"* ]]
	[[ "$output" == *"Reuse existing Codex worktrees|"* ]]
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

@test "_cwt_require_git: relative worktree dir resolves from git root" {
	create_test_repo
	mkdir -p "$REPO_DIR/apps/api"
	local repo_real
	local expected_dir
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)/shared-worktrees"

	run zsh -c "
    export NO_COLOR=1
    export CWT_WORKTREE_DIR='../shared-worktrees'
    source '$CWT_SH'
    cd '$REPO_DIR/apps/api'
    _cwt_require_git
    echo \"git_root=\$_cwt_git_root\"
    echo \"worktrees_dir=\$_cwt_worktrees_dir\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"git_root=$repo_real"* ]]
	[[ "$output" == *"worktrees_dir=$expected_dir"* ]]
}

@test "_cwt_require_git: relative worktree dir resolves from main git root in linked worktree" {
	create_test_repo
	git -C "$REPO_DIR" worktree add "$REPO_DIR/wt-linked" -b wt-linked main >/dev/null
	local repo_real
	local expected_dir
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)/shared-worktrees"

	run zsh -c "
    export NO_COLOR=1
    export CWT_WORKTREE_DIR='../shared-worktrees'
    source '$CWT_SH'
    cd '$REPO_DIR/wt-linked'
    _cwt_require_git
    echo \"git_root=\$_cwt_git_root\"
    echo \"worktrees_dir=\$_cwt_worktrees_dir\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"git_root=$repo_real"* ]]
	[[ "$output" == *"worktrees_dir=$expected_dir"* ]]
}

@test "_cwt_require_git: config model binds defaults and current project settings" {
	create_test_repo
	local repo_real
	local expected_dir
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)/repo-worktrees"

	mkdir -p "$XDG_CONFIG_HOME/cwt"
	cat >"$XDG_CONFIG_HOME/cwt/config.yaml" <<EOF
version: 1
defaults:
  default_assistant: 'codex'
  launch_target: 'tab'
projects:
  - git_root: '/tmp/already-configured'
    worktree_dir: '../other-worktrees'
  - git_root: '$repo_real'
    worktree_dir: '../repo-worktrees'
EOF

	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    cd '$REPO_DIR'
    _cwt_require_git
    echo \"project_dir=\$_cwt_config_current_project_worktree_dir\"
    echo \"assistant=\$(_cwt_default_assistant)\"
    echo \"launch_target=\$(_cwt_default_launch_target)\"
    echo \"worktrees_dir=\$_cwt_worktrees_dir\"
    _cwt_has_project_config
    echo \"has_project=\$?\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"project_dir=../repo-worktrees"* ]]
	[[ "$output" == *"assistant=codex"* ]]
	[[ "$output" == *"launch_target=tab"* ]]
	[[ "$output" == *"worktrees_dir=$expected_dir"* ]]
	[[ "$output" == *"has_project=0"* ]]
}

@test "_cwt_select_index_interactive: uses fzf when available" {
	install_fake_fzf
	printf '%s\n' "rm-fzf" >"$TEST_TMPDIR/fzf-matches"

	run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_FZF=1
    export CWT_TEST_FZF_MATCH_FILE='$TEST_TMPDIR/fzf-matches'
    export PATH='$TEST_TMPDIR/bin':\"\$PATH\"
    source '$CWT_SH'
    selected=\$(_cwt_select_index_interactive 'Worktree > ' 'Select worktree:' 'Choice: ' '' main rm-fzf other)
    echo \"selected=\$selected\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"selected=2"* ]]
}

@test "_cwt_select_index_interactive: numbered fallback applies the default choice" {
	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    selected=\$(printf '\n' | _cwt_select_index_interactive 'Base branch > ' 'Select base branch:' 'Choice (default: 1=HEAD): ' '1' HEAD main)
    echo \"selected=\$selected\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"selected=1"* ]]
}

@test "_cwt_worktree_root_action_records: builds suggested current up and child entries" {
	create_test_repo
	mkdir -p "$TEST_TMPDIR/shared"

	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_git_root='$REPO_DIR'
    _cwt_worktree_root_action_records '$TEST_TMPDIR' 'repo'
    for record in \"\${reply[@]}\"; do
      echo \"kind=\$(_cwt_record_kind \"\$record\") value=\$(_cwt_record_value \"\$record\") label=\$(_cwt_record_label \"\$record\")\"
    done
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"kind=suggested"* ]]
	[[ "$output" == *"label=Create or use $TEST_TMPDIR/repo-worktrees"* ]]
	[[ "$output" == *"kind=current"* ]]
	[[ "$output" == *"label=Use $TEST_TMPDIR as the worktree root"* ]]
	[[ "$output" == *"kind=up"* ]]
	[[ "$output" == *"kind=child"* ]]
	[[ "$output" == *"label=Browse shared/"* ]]
}

@test "_cwt_setup_option_records: includes legacy detected browse and skip entries" {
	create_test_repo
	mkdir -p "$REPO_DIR/.claude/worktrees"

	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_git_root='$REPO_DIR'
    _cwt_config_legacy_worktree_dir='../legacy-worktrees'
    _cwt_setup_option_records
    for record in \"\${reply[@]}\"; do
      echo \"kind=\$(_cwt_record_kind \"\$record\") label=\$(_cwt_record_label \"\$record\")\"
    done
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"kind=legacy label=Use the legacy cwt setting for this project: ../legacy-worktrees"* ]]
	[[ "$output" == *"kind=detected label=Reuse existing Claude worktrees:"* ]]
	[[ "$output" == *"kind=browse label=Browse for another worktree folder"* ]]
	[[ "$output" == *"kind=skip label=Not now. Use the default for this run only"* ]]
}

@test "_cwt_parse_shared_launch_option: returns updated launch state through reply" {
	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_parse_shared_launch_option '--assistant' 'codex' 'claude' 'current' 'default' '0'
    echo \"assistant=\${reply[1]}\"
    echo \"target=\${reply[2]}\"
    echo \"permission=\${reply[3]}\"
    echo \"explicit=\${reply[4]}\"
    echo \"consumed=\${reply[5]}\"
    echo \"requested=\${reply[6]}\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"assistant=codex"* ]]
	[[ "$output" == *"target=current"* ]]
	[[ "$output" == *"permission=default"* ]]
	[[ "$output" == *"explicit=0"* ]]
	[[ "$output" == *"consumed=2"* ]]
	[[ "$output" == *"requested=1"* ]]
}

@test "_cwt_collect_managed_worktrees: accepts explicit git and worktree roots" {
	create_test_repo
	mkdir -p "$REPO_DIR/.worktrees"
	git -C "$REPO_DIR" worktree add "$REPO_DIR/.worktrees/feature" -b feature main >/dev/null
	local expected_path
	expected_path="$(cd "$REPO_DIR/.worktrees/feature" && pwd -P)"

	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_git_root='/tmp/not-the-repo'
    _cwt_worktrees_dir='/tmp/not-the-worktrees'
    _cwt_collect_managed_worktrees '$REPO_DIR' '$REPO_DIR/.worktrees'
    echo \"names=\${_cwt_worktree_names_cache[*]}\"
    echo \"path=\$(_cwt_worktree_path_from_name feature)\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"names=feature"* ]]
	[[ "$output" == *"path=$expected_path"* ]]
}

@test "completion helpers: resolve project worktree dir via shared config helpers" {
	create_test_repo
	local repo_real
	local expected_dir
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)/repo-worktrees"

	mkdir -p "$XDG_CONFIG_HOME/cwt"
	cat >"$XDG_CONFIG_HOME/cwt/config.yaml" <<EOF
version: 1
projects:
  - git_root: '$repo_real'
    worktree_dir: '../repo-worktrees'
EOF

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$PROJECT_DIR/completions/_cwt'
    echo \"project_dir=\$(_cwt_project_worktree_dir)\"
    echo \"resolved_dir=\$(_cwt_resolve_worktree_dir)\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"project_dir=../repo-worktrees"* ]]
	[[ "$output" == *"resolved_dir=$expected_dir"* ]]
}

@test "completion helpers: default to .worktrees when only legacy config exists" {
	create_test_repo
	local expected_dir
	expected_dir="$(cd "$REPO_DIR" && pwd -P)/.worktrees"

	mkdir -p "$XDG_CONFIG_HOME/cwt"
	cat >"$XDG_CONFIG_HOME/cwt/config" <<'EOF'
export CWT_WORKTREE_DIR='../legacy-worktrees'
EOF

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$PROJECT_DIR/completions/_cwt'
    echo \"resolved_dir=\$(_cwt_resolve_worktree_dir)\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"resolved_dir=$expected_dir"* ]]
}

@test "sourcing cwt after compinit keeps cwt completion autoloadable" {
	local expected_completion_dir
	expected_completion_dir="$(cd "$PROJECT_DIR/completions" && pwd -P)"

	run zsh -c "
    export NO_COLOR=1
    autoload -Uz compinit
    compinit -D
    source '$CWT_SH'
    echo \"has_completion_dir=\$(( \${fpath[(Ie)$expected_completion_dir]} > 0 ))\"
    autoload -Uz +X _cwt
    echo \"completion_loaded=\$(( \$+functions[_cwt] > 0 ))\"
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"has_completion_dir=1"* ]]
	[[ "$output" == *"completion_loaded=1"* ]]
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

@test "_cwt_is_valid_launch_target: accepts supported targets" {
	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_is_valid_launch_target current
    echo \"current=\$?\"
    _cwt_is_valid_launch_target split
    echo \"split=\$?\"
    _cwt_is_valid_launch_target tab
    echo \"tab=\$?\"
  "
	[ "$status" -eq 0 ]
	[[ "$output" == *"current=0"* ]]
	[[ "$output" == *"split=0"* ]]
	[[ "$output" == *"tab=0"* ]]
}

@test "_cwt_is_valid_launch_target: rejects unknown target" {
	run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    _cwt_is_valid_launch_target pane
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

@test "cwt with no command runs setup wizard inside a git repo when forced" {
	create_test_repo

	run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_SETUP_WIZARD=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    printf '\n' | cwt
  "

	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/cwt/config.yaml" ]
	[[ "$output" == *"No cwt config found for this project"* ]]
	[[ "$output" == *"Saved cwt config"* ]]
}

@test "cwt with no command outside a git repo still shows usage" {
	run zsh -c "
    export NO_COLOR=1
    cd '$TEST_TMPDIR'
    source '$CWT_SH'
    cwt
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
