#!/usr/bin/env bats
# Tests for cwt config

setup() {
	load test_helper
	setup
	create_test_repo
}

teardown() {
	teardown
}

@test "cwt config --help: shows help" {
	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config --help
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"cwt config"* ]]
	[[ "$output" == *"worktree root"* ]]
	[[ "$output" == *"--browse"* ]]
}

@test "cwt config --show: shows current project summary" {
	local repo_real
	repo_real="$(cd "$REPO_DIR" && pwd -P)"

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config --show
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Current cwt config for this project"* ]]
	[[ "$output" == *"Stored worktree root: <none>"* ]]
	[[ "$output" == *"Active worktree root: $repo_real/.worktrees"* ]]
}

@test "cwt config: saves an explicit worktree root for the current project" {
	local repo_real expected_root
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_root="$(cd "$TEST_TMPDIR" && pwd -P)/shared-worktrees"

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config ../shared-worktrees
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Saved cwt config"* ]]
	[[ "$output" == *"Worktree root: $expected_root"* ]]
	run grep -q "git_root: '$repo_real'" "$XDG_CONFIG_HOME/cwt/config.yaml"
	[ "$status" -eq 0 ]
	run grep -q "worktree_dir: '../shared-worktrees'" "$XDG_CONFIG_HOME/cwt/config.yaml"
	[ "$status" -eq 0 ]
}

@test "cwt config --default: resets a custom project worktree root" {
	local repo_real
	repo_real="$(cd "$REPO_DIR" && pwd -P)"

	mkdir -p "$XDG_CONFIG_HOME/cwt"
	cat >"$XDG_CONFIG_HOME/cwt/config.yaml" <<EOF
version: 1
projects:
  - git_root: '$repo_real'
    worktree_dir: '../shared-worktrees'
EOF

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config --default
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Worktree root: $REPO_DIR/.worktrees"* ]]
	run grep -q "worktree_dir: '.worktrees'" "$XDG_CONFIG_HOME/cwt/config.yaml"
	[ "$status" -eq 0 ]
}

@test "cwt config --browse: can pick a worktree root interactively" {
	install_fake_fzf
	local expected_root
	expected_root="$(cd "$TEST_TMPDIR" && pwd -P)/shared"
	mkdir -p "$expected_root"

	printf '%s\n%s\n' \
		"Browse shared/" \
		"Use ${expected_root} as the worktree root" >"$TEST_TMPDIR/fzf-matches"

	run zsh -c "
    export NO_COLOR=1
    export CWT_FORCE_FZF=1
    export CWT_TEST_FZF_MATCH_FILE='$TEST_TMPDIR/fzf-matches'
    export PATH='$TEST_TMPDIR/bin':\"\$PATH\"
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config --browse
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Worktree root: $expected_root"* ]]
	run grep -q "worktree_dir: '../shared'" "$XDG_CONFIG_HOME/cwt/config.yaml"
	[ "$status" -eq 0 ]
}

@test "cwt config --show: reads legacy config path when config.yaml is absent" {
	local repo_real expected_root
	repo_real="$(cd "$REPO_DIR" && pwd -P)"
	expected_root="$(cd "$TEST_TMPDIR" && pwd -P)/shared-worktrees"

	mkdir -p "$XDG_CONFIG_HOME/cwt"
	cat >"$XDG_CONFIG_HOME/cwt/config" <<EOF
version: 1
projects:
  - git_root: '$repo_real'
    worktree_dir: '../shared-worktrees'
EOF

	run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt config --show
  "

	[ "$status" -eq 0 ]
	[[ "$output" == *"Stored worktree root: ../shared-worktrees"* ]]
	[[ "$output" == *"Active worktree root: $expected_root"* ]]
}
