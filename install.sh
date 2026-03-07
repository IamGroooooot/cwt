#!/bin/sh
# cwt installer
# Usage: curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
set -e

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok() { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }
err() { printf " %s✗%s %s\n" "$RED" "$NC" "$*" >&2; }

CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
REPO="${CWT_REPO:-https://github.com/IamGroooooot/cwt.git}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
CWT_BLOCK_START="# cwt - AI Worktree Manager"
CWT_BLOCK_END="# /cwt - AI Worktree Manager"
LEGACY_HEADER="# cwt - Claude Worktree Manager"
# shellcheck disable=SC2016
LEGACY_FPATH_LINE='fpath=("$HOME/.cwt/completions" $fpath)'
# shellcheck disable=SC2016
LEGACY_SOURCE_LINE='[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"'
COMPINIT_LINE='autoload -Uz compinit && compinit'
SHELL_FPATH_LINE=""
SHELL_SOURCE_LINE=""
AUTO_YES=0

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

shell_profile_cwt_dir() {
	default_install_dir=$(resolve_target_dir "$HOME/.cwt" 2>/dev/null || printf '%s' "$HOME/.cwt")

	if [ "$CWT_DIR" = "$default_install_dir" ]; then
		# shellcheck disable=SC2016
		printf '%s' '$HOME/.cwt'
		return 0
	fi

	printf '%s' "$CWT_DIR"
}

prepare_shell_profile_lines() {
	profile_cwt_dir=$(shell_profile_cwt_dir)
	# shellcheck disable=SC2016
	SHELL_FPATH_LINE=$(printf 'fpath=("%s/completions" $fpath)' "$profile_cwt_dir")
	SHELL_SOURCE_LINE=$(printf '[[ -f "%s/cwt.sh" ]] && source "%s/cwt.sh"' "$profile_cwt_dir" "$profile_cwt_dir")
}

parse_args() {
	for arg in "$@"; do
		case "$arg" in
		-y | --yes) AUTO_YES=1 ;;
		esac
	done
}

ensure_prerequisites() {
	command -v git >/dev/null 2>&1 || {
		err "git is required. Install: apt install git / brew install git"
		exit 1
	}
	command -v zsh >/dev/null 2>&1 || {
		err "zsh is required. Install: apt install zsh / brew install zsh"
		exit 1
	}

	normalize_install_dir
	refuse_unsafe_install_dir
	prepare_shell_profile_lines
}

confirm_installation() {
	[ -t 0 ] || return 0
	[ "$AUTO_YES" -eq 0 ] || return 0

	echo "  This will:"
	if [ -d "$CWT_DIR" ]; then
		printf "    • Update cwt in %s\n" "$CWT_DIR"
	else
		printf "    • Clone cwt to %s\n" "$CWT_DIR"
	fi
	printf "    • Add source line to %s\n" "$ZSHRC"
	echo ""
	printf "  Continue? [Y/n] "
	read -r REPLY
	case "$REPLY" in
	n* | N*)
		echo ""
		info "Cancelled."
		exit 0
		;;
	esac
	echo ""
}

clone_cwt_checkout() {
	git clone --depth 1 --quiet "$REPO" "$CWT_DIR"
}

install_or_update_cwt() {
	if [ ! -d "$CWT_DIR" ]; then
		info "Installing cwt to ${DIM}${CWT_DIR}${NC}..."
		clone_cwt_checkout
		ok "Cloned."
		return 0
	fi

	info "Updating cwt..."
	if git -C "$CWT_DIR" pull --quiet --ff-only 2>/dev/null; then
		ok "Updated."
		return 0
	fi

	info "Pull failed, re-cloning..."
	rm -rf "$CWT_DIR"
	clone_cwt_checkout
	ok "Updated."
}

remove_existing_cwt_shell_config() {
	profile_path="$1"
	temp_profile="${profile_path}.tmp.$$"

	[ -f "$profile_path" ] || return 0

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

append_cwt_shell_config() {
	profile_path="$1"

	{
		printf '\n%s\n' "$CWT_BLOCK_START"
		printf '%s\n' "$SHELL_FPATH_LINE"
		printf '%s\n' "$SHELL_SOURCE_LINE"
		printf '%s\n' "$CWT_BLOCK_END"
	} >>"$profile_path"
}

ensure_shell_profile_exists() {
	profile_dir=$(dirname "$ZSHRC")
	mkdir -p "$profile_dir"
	touch "$ZSHRC"
}

configure_shell_profile() {
	ensure_shell_profile_exists

	if shell_profile_has_cwt_config; then
		remove_existing_cwt_shell_config "$ZSHRC"
		append_cwt_shell_config "$ZSHRC"
		ok "Updated ${ZSHRC}"
	else
		append_cwt_shell_config "$ZSHRC"
		ok "Added to ${ZSHRC}"
	fi

	if ! grep -qF 'compinit' "$ZSHRC" 2>/dev/null; then
		printf '%s\n' "$COMPINIT_LINE" >>"$ZSHRC"
		ok "Added compinit to ${ZSHRC}"
	fi
}

print_summary() {
	echo ""
	ok "cwt installed successfully!"
	echo ""
	info "Restart your shell or run:"
	printf "   %ssource %s%s\n" "$BOLD" "$ZSHRC" "$NC"
	echo ""
}

main() {
	parse_args "$@"
	ensure_prerequisites

	echo ""
	printf " %scwt%s %sinstaller%s\n" "$BOLD" "$NC" "$DIM" "$NC"
	echo ""

	confirm_installation
	install_or_update_cwt
	configure_shell_profile
	print_summary
}

main "$@"
