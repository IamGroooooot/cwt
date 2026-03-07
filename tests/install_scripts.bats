#!/usr/bin/env bats
# Tests for install.sh and uninstall.sh

setup() {
	load test_helper
	setup
}

teardown() {
	teardown
}

@test "install.sh: rejects unsafe CWT_DIR" {
	run env HOME="$TEST_TMPDIR" ZDOTDIR="$TEST_TMPDIR" CWT_DIR=/ sh "$INSTALL_SH" --yes
	[ "$status" -eq 1 ]
	[[ "$output" == *"Refusing to use unsafe CWT_DIR: /"* ]]
}

@test "install.sh: custom CWT_DIR writes shell config for that install" {
	local install_dir="$TEST_TMPDIR/tools/cwt"
	local resolved_install_dir

	run env \
		HOME="$TEST_TMPDIR" \
		ZDOTDIR="$TEST_TMPDIR" \
		CWT_DIR="$install_dir" \
		CWT_REPO="$PROJECT_DIR" \
		sh "$INSTALL_SH" --yes

	[ "$status" -eq 0 ]
	[ -d "$install_dir" ]
	resolved_install_dir="$(cd "$install_dir" && pwd -P)"
	[ -f "$TEST_TMPDIR/.zshrc" ]
	run grep -F "fpath=(\"$resolved_install_dir/completions\" \$fpath)" "$TEST_TMPDIR/.zshrc"
	[ "$status" -eq 0 ]
	run grep -F "[[ -f \"$resolved_install_dir/cwt.sh\" ]] && source \"$resolved_install_dir/cwt.sh\"" "$TEST_TMPDIR/.zshrc"
	[ "$status" -eq 0 ]
}

@test "install.sh: reinstall refreshes managed shell block" {
	local first_install_dir="$TEST_TMPDIR/tools/cwt-one"
	local second_install_dir="$TEST_TMPDIR/tools/cwt-two"
	local resolved_second_install_dir

	run env \
		HOME="$TEST_TMPDIR" \
		ZDOTDIR="$TEST_TMPDIR" \
		CWT_DIR="$first_install_dir" \
		CWT_REPO="$PROJECT_DIR" \
		sh "$INSTALL_SH" --yes
	[ "$status" -eq 0 ]

	run env \
		HOME="$TEST_TMPDIR" \
		ZDOTDIR="$TEST_TMPDIR" \
		CWT_DIR="$second_install_dir" \
		CWT_REPO="$PROJECT_DIR" \
		sh "$INSTALL_SH" --yes
	[ "$status" -eq 0 ]

	[ -f "$TEST_TMPDIR/.zshrc" ]
	run grep -F "$first_install_dir" "$TEST_TMPDIR/.zshrc"
	[ "$status" -ne 0 ]
	resolved_second_install_dir="$(cd "$second_install_dir" && pwd -P)"
	run grep -F "$resolved_second_install_dir" "$TEST_TMPDIR/.zshrc"
	[ "$status" -eq 0 ]
}

@test "uninstall.sh: removes custom install and managed shell block" {
	local install_dir="$TEST_TMPDIR/tools/cwt"

	run env \
		HOME="$TEST_TMPDIR" \
		ZDOTDIR="$TEST_TMPDIR" \
		CWT_DIR="$install_dir" \
		CWT_REPO="$PROJECT_DIR" \
		sh "$INSTALL_SH" --yes
	[ "$status" -eq 0 ]
	[ -d "$install_dir" ]

	run env HOME="$TEST_TMPDIR" ZDOTDIR="$TEST_TMPDIR" CWT_DIR="$install_dir" sh "$UNINSTALL_SH"
	[ "$status" -eq 0 ]
	[ ! -d "$install_dir" ]
	run grep -F "$install_dir" "$TEST_TMPDIR/.zshrc"
	[ "$status" -ne 0 ]
	run grep -F "# cwt - AI Worktree Manager" "$TEST_TMPDIR/.zshrc"
	[ "$status" -ne 0 ]
}
