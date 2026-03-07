#!/bin/sh
# cwt uninstaller
set -e

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok() { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }
err() { printf " %s✗%s %s\n" "$RED" "$NC" "$*" >&2; }

CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
CWT_BLOCK_START="# cwt - AI Worktree Manager"
CWT_BLOCK_END="# /cwt - AI Worktree Manager"
LEGACY_HEADER="# cwt - Claude Worktree Manager"
# shellcheck disable=SC2016
LEGACY_FPATH_LINE='fpath=("$HOME/.cwt/completions" $fpath)'
# shellcheck disable=SC2016
LEGACY_SOURCE_LINE='[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"'

resolve_target_dir() {
	target="$1"

	[ -n "$target" ] || return 1

	if [ -d "$target" ]; then
		(
			cd "$target" 2>/dev/null && pwd -P
		)
		return $?
	fi

	target_parent=$(dirname "$target")
	[ "$target_parent" != "$target" ] || return 1
	target_base=$(basename "$target")
	resolved_parent=$(resolve_target_dir "$target_parent") || return 1

	printf '%s/%s\n' "$resolved_parent" "$target_base"
}

normalize_install_dir() {
	CWT_DIR=$(resolve_target_dir "$CWT_DIR") || {
		err "Refusing to use unsafe CWT_DIR: $CWT_DIR"
		exit 1
	}
}

refuse_unsafe_install_dir() {
	case "$CWT_DIR" in
	/ | "$HOME")
		err "Refusing to use unsafe CWT_DIR: $CWT_DIR"
		exit 1
		;;
	esac
}

remove_existing_cwt_shell_config() {
	profile_path="$1"
	temp_profile="${profile_path}.tmp.$$"

	[ -f "$profile_path" ] || return 1

	awk '
    BEGIN { skip = 0 }
    $0 == block_start { skip = 1; next }
    $0 == block_end { skip = 0; next }
    skip { next }
    $0 == block_header { next }
    $0 == legacy_header { next }
    $0 == legacy_fpath { next }
    $0 == legacy_source { next }
    { print }
  ' \
		block_start="$CWT_BLOCK_START" \
		block_end="$CWT_BLOCK_END" \
		block_header="$CWT_BLOCK_START" \
		legacy_header="$LEGACY_HEADER" \
		legacy_fpath="$LEGACY_FPATH_LINE" \
		legacy_source="$LEGACY_SOURCE_LINE" \
		"$profile_path" >"$temp_profile"

	mv "$temp_profile" "$profile_path"
}

shell_profile_has_cwt_config() {
	[ -f "$ZSHRC" ] || return 1

	grep -qF "$CWT_BLOCK_START" "$ZSHRC" 2>/dev/null ||
		grep -qF "$LEGACY_SOURCE_LINE" "$ZSHRC" 2>/dev/null ||
		grep -qF "$LEGACY_HEADER" "$ZSHRC" 2>/dev/null
}

remove_installation_dir() {
	if [ -d "$CWT_DIR" ]; then
		rm -rf "$CWT_DIR"
		ok "Removed ${CWT_DIR}"
		return 0
	fi

	info "No cwt directory found."
}

remove_shell_profile_config() {
	if shell_profile_has_cwt_config; then
		remove_existing_cwt_shell_config "$ZSHRC"
		ok "Removed cwt from ${ZSHRC}"
	fi
}

print_summary() {
	echo ""
	ok "cwt uninstalled."
	echo ""
}

main() {
	normalize_install_dir
	refuse_unsafe_install_dir

	echo ""
	remove_installation_dir
	remove_shell_profile_config
	print_summary
}

main "$@"
