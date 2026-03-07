#!/usr/bin/env zsh
# shellcheck disable=SC1009,SC1036,SC1058,SC1072,SC1073
# ↑ zsh glob qualifiers like (N) and ${var:t} can't be parsed by ShellCheck
# ─────────────────────────────────────────────────────────────────────────────
# cwt - AI Worktree Manager
# Manage git worktrees for parallel AI coding sessions.
#
# Install:
#   source "$HOME/.cwt/cwt.sh"
#
# Usage:
#   cwt new [name] [base] [branch]   Create a worktree
#   cwt ls                           List worktrees
#   cwt cd [name]                    Enter a worktree
#   cwt rm [name]                    Remove a worktree
#   cwt update                       Self-update cwt
#   cwt --help                       Show help
# ─────────────────────────────────────────────────────────────────────────────

CWT_VERSION="0.2.16"

# ── ANSI color utilities ────────────────────────────────────────────────────
# Respects NO_COLOR (https://no-color.org/) and non-interactive pipes
# Checks stderr (-t 2) since informational output is routed there.

if [[ -z "$NO_COLOR" ]] && [[ -t 2 ]]; then
  _cwt_red()     { printf '\033[0;31m%s\033[0m' "$*"; }
  _cwt_green()   { printf '\033[0;32m%s\033[0m' "$*"; }
  _cwt_yellow()  { printf '\033[0;33m%s\033[0m' "$*"; }
  _cwt_blue()    { printf '\033[0;34m%s\033[0m' "$*"; }
  _cwt_cyan()    { printf '\033[0;36m%s\033[0m' "$*"; }
  _cwt_dim()     { printf '\033[2m%s\033[0m' "$*"; }
  _cwt_bold()    { printf '\033[1m%s\033[0m' "$*"; }
else
  _cwt_red()     { printf '%s' "$*"; }
  _cwt_green()   { printf '%s' "$*"; }
  _cwt_yellow()  { printf '%s' "$*"; }
  _cwt_blue()    { printf '%s' "$*"; }
  _cwt_cyan()    { printf '%s' "$*"; }
  _cwt_dim()     { printf '%s' "$*"; }
  _cwt_bold()    { printf '%s' "$*"; }
fi

# ── Logging helpers ─────────────────────────────────────────────────────────
# All informational output goes to stderr so stdout remains pipeable.
# _cwt_log_info and _cwt_log_item respect CWT_QUIET (set by -q/--quiet).

_cwt_log_success() { echo " $(_cwt_green '✓') $*" >&2; }
_cwt_log_error()   { echo " $(_cwt_red '✗') $*" >&2; }
_cwt_log_info()    { [[ ${CWT_QUIET:-0} -eq 1 ]] && return; echo " $(_cwt_cyan '→') $*" >&2; }
_cwt_log_warn()    { echo " $(_cwt_yellow '!') $*" >&2; }
_cwt_log_item()    { [[ ${CWT_QUIET:-0} -eq 1 ]] && return; echo "   $(_cwt_dim '•') $*" >&2; }

# ── Config loader ─────────────────────────────────────────────────────────

_cwt_config_file_path() {
  print -r -- "${CWT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cwt/config}"
}

_cwt_load_config() {
  local config_file
  config_file=$(_cwt_config_file_path)
  [[ -f "$config_file" ]] && source "$config_file"
}

_cwt_is_interactive() {
  [[ -t 0 ]]
}

_cwt_prompt_choice() {
  local prompt="$1"
  local default_choice="$2"
  local choice

  echo -n "$(_cwt_cyan '?') $prompt" >&2
  IFS= read -r choice
  [[ -z "$choice" ]] && choice="$default_choice"
  print -r -- "$choice"
}

_cwt_confirm() {
  local prompt="$1"
  local default_answer="${2:-n}"
  local choice

  if [[ "$default_answer" == "y" ]]; then
    choice=$(_cwt_prompt_choice "$prompt [Y/n]: " "y")
  else
    choice=$(_cwt_prompt_choice "$prompt [y/N]: " "n")
  fi

  case "${choice:l}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Relative time helper ───────────────────────────────────────────────────

_cwt_relative_time() {
  local timestamp="$1"
  local now=$(date +%s)
  local diff=$(( now - timestamp ))

  if (( diff < 60 )); then
    echo "just now"
  elif (( diff < 3600 )); then
    echo "$(( diff / 60 ))m ago"
  elif (( diff < 86400 )); then
    echo "$(( diff / 3600 ))h ago"
  elif (( diff < 604800 )); then
    echo "$(( diff / 86400 ))d ago"
  else
    echo "$(( diff / 604800 ))w ago"
  fi
}

# ── Git context helper ─────────────────────────────────────────────────────

_cwt_relative_path_from() {
  local base_dir="${1:A}"
  local target_dir="${2:A}"
  local -a base_parts=()
  local -a target_parts=()
  local -a relative_parts=()
  local common_parts=0
  local index

  [[ "$base_dir" == "$target_dir" ]] && {
    print -r -- "."
    return 0
  }

  [[ "$base_dir" != "/" ]] && base_parts=("${(@s:/:)${base_dir#/}}")
  [[ "$target_dir" != "/" ]] && target_parts=("${(@s:/:)${target_dir#/}}")

  while (( common_parts < ${#base_parts[@]} && common_parts < ${#target_parts[@]} )); do
    if [[ "${base_parts[$((common_parts + 1))]}" != "${target_parts[$((common_parts + 1))]}" ]]; then
      break
    fi
    ((common_parts++))
  done

  for (( index = common_parts + 1; index <= ${#base_parts[@]}; index++ )); do
    relative_parts+=("..")
  done

  for (( index = common_parts + 1; index <= ${#target_parts[@]}; index++ )); do
    relative_parts+=("${target_parts[$index]}")
  done

  if (( ${#relative_parts[@]} == 0 )); then
    print -r -- "."
  else
    print -r -- "${(j:/:)relative_parts}"
  fi
}

_cwt_resolve_worktrees_dir() {
  local configured_dir="${CWT_WORKTREE_DIR:-}"
  local resolved_dir

  if [[ -z "$configured_dir" ]]; then
    resolved_dir="${_cwt_git_root}/.worktrees"
  else
    resolved_dir="$configured_dir"
    case "$resolved_dir" in
      "~")
        resolved_dir="$HOME"
        ;;
      "~/"*)
        resolved_dir="$HOME/${resolved_dir#~/}"
        ;;
      /*)
        ;;
      *)
        resolved_dir="${_cwt_git_root}/${resolved_dir}"
        ;;
    esac
  fi

  print -r -- "${resolved_dir:A}"
}

_cwt_worktrees_config_value() {
  local worktrees_dir="${1:A}"
  print -r -- "$(_cwt_relative_path_from "$_cwt_git_root" "$worktrees_dir")"
}

_cwt_validate_worktrees_dir() {
  local worktrees_dir="$1"

  if [[ -z "$worktrees_dir" || "$worktrees_dir" == "/" ]]; then
    _cwt_log_error "Unsafe worktree root: $(_cwt_bold "${worktrees_dir:-<empty>}")."
    _cwt_log_item "Choose a dedicated directory such as $(_cwt_bold '../projectA-worktrees') or $(_cwt_bold '$HOME/worktrees/projectA')."
    return 1
  fi

  if [[ "$worktrees_dir" == "$_cwt_git_root" ]]; then
    _cwt_log_error "Custom worktree root cannot be the git root itself."
    _cwt_log_item "Use a sibling or dedicated directory instead, for example $(_cwt_bold '../projectA-worktrees')."
    return 1
  fi

  if [[ "$worktrees_dir" == "${_cwt_git_root}/.git" || "$worktrees_dir" == "${_cwt_git_root}/.git/"* ]]; then
    _cwt_log_error "Custom worktree root cannot live inside $(_cwt_bold '.git')."
    _cwt_log_item "Use a normal directory outside git metadata, for example $(_cwt_bold '../projectA-worktrees')."
    return 1
  fi
}

_cwt_print_detected_worktree_roots() {
  local candidate label path
  local -a detected_paths=()

  for candidate in \
    "Reuse existing Claude worktrees|${_cwt_git_root}/.claude/worktrees" \
    "Reuse existing Codex worktrees|${_cwt_git_root}/.codex/worktrees"
  do
    label="${candidate%%|*}"
    path="${candidate#*|}"

    [[ -d "$path" ]] || continue
    [[ " ${detected_paths[*]} " == *" $path "* ]] && continue

    detected_paths+=("$path")
    print -r -- "${label}|${path:A}"
  done
}

_cwt_read_browse_key() {
  local key
  local next_key
  local final_key

  IFS= read -rk1 -u 0 key || return 1

  case "$key" in
    $'\n'|$'\r')
      print -r -- "enter"
      ;;
    q|Q)
      print -r -- "quit"
      ;;
    h)
      print -r -- "left"
      ;;
    j)
      print -r -- "down"
      ;;
    k)
      print -r -- "up"
      ;;
    l)
      print -r -- "right"
      ;;
    $'\e')
      IFS= read -rk1 -u 0 -t 0.01 next_key || {
        print -r -- "quit"
        return 0
      }
      if [[ "$next_key" == "[" ]]; then
        IFS= read -rk1 -u 0 -t 0.01 final_key || {
          print -r -- "quit"
          return 0
        }
        case "$final_key" in
          A) print -r -- "up" ;;
          B) print -r -- "down" ;;
          C) print -r -- "right" ;;
          D) print -r -- "left" ;;
          *) print -r -- "other" ;;
        esac
      else
        print -r -- "quit"
      fi
      ;;
    *)
      print -r -- "other"
      ;;
  esac
}

_cwt_browse_for_worktree_root() {
  local browse_dir="${_cwt_git_root:h}"
  local repo_name="${_cwt_git_root:t}"
  local suggested_dir
  local chosen_dir
  local key
  local index
  local selected_index=1
  local -a child_dirs=()
  local -a action_kinds=()
  local -a action_values=()
  local -a action_labels=()

  while true; do
    suggested_dir="${browse_dir}/${repo_name}-worktrees"
    child_dirs=("$browse_dir"/*(/N))

    action_kinds=("suggested" "current")
    action_values=("$suggested_dir" "$browse_dir")
    action_labels=("Create or use ${suggested_dir}" "Use ${browse_dir} as the worktree root")

    for chosen_dir in "${child_dirs[@]}"; do
      action_kinds+=("child")
      action_values+=("$chosen_dir")
      action_labels+=("${chosen_dir:t}/")
    done

    (( selected_index < 1 )) && selected_index=1
    (( selected_index > ${#action_kinds[@]} )) && selected_index=${#action_kinds[@]}

    if [[ -t 2 ]]; then
      printf '\033[2J\033[H' >&2
    fi

    echo "" >&2
    _cwt_log_info "Browse for a worktree folder."
    _cwt_log_item "Current location: $(_cwt_dim "$browse_dir")"
    _cwt_log_item "← up  → enter folder  ↑/↓ move  Enter select  q cancel"
    echo "" >&2

    for (( index = 1; index <= ${#action_kinds[@]}; index++ )); do
      if (( index == selected_index )); then
        echo "   $(_cwt_cyan '>') ${action_labels[$index]}" >&2
      else
        echo "     ${action_labels[$index]}" >&2
      fi
    done

    key=$(_cwt_read_browse_key) || return 1
    case "$key" in
      up)
        (( selected_index > 1 )) && ((selected_index--))
        ;;
      down)
        (( selected_index < ${#action_kinds[@]} )) && ((selected_index++))
        ;;
      left)
        if [[ "$browse_dir" != "/" ]]; then
          browse_dir="${browse_dir:h}"
          selected_index=1
        fi
        ;;
      right)
        if [[ "${action_kinds[$selected_index]}" == "child" ]]; then
          browse_dir="${action_values[$selected_index]}"
          selected_index=1
        fi
        ;;
      enter)
        case "${action_kinds[$selected_index]}" in
          child)
            browse_dir="${action_values[$selected_index]}"
            selected_index=1
            ;;
          suggested|current)
            chosen_dir="${action_values[$selected_index]:A}"
            if [[ "${action_kinds[$selected_index]}" == "current" && "$chosen_dir" == "${_cwt_git_root:h}" ]]; then
              _cwt_confirm "Use $chosen_dir directly? Worktrees will sit beside your projects." || continue
            fi
            _cwt_validate_worktrees_dir "$chosen_dir" || continue
            mkdir -p "$chosen_dir" 2>/dev/null || {
              _cwt_log_error "Failed to create $(_cwt_bold "$chosen_dir")."
              continue
            }
            print -r -- "$chosen_dir"
            return 0
            ;;
        esac
        ;;
      quit)
        return 1
        ;;
    esac
  done
}

_cwt_write_setup_config() {
  local config_file="$1"
  local config_value="$2"

  mkdir -p "${config_file:h}" 2>/dev/null || {
    _cwt_log_warn "Could not create $(_cwt_bold "${config_file:h}")."
    return 1
  }

  {
    print -r -- "# cwt config"
    print -r -- "# Created by the cwt first-run setup wizard."
    print -r -- ""
    if [[ -n "$config_value" ]]; then
      printf "CWT_WORKTREE_DIR=%q\n" "$config_value"
    else
      print -r -- "# Using the default worktree root under <git-root>/.worktrees"
    fi
  } >| "$config_file" 2>/dev/null || {
    _cwt_log_warn "Could not write $(_cwt_bold "$config_file")."
    return 1
  }
}

_cwt_apply_setup_choice() {
  local config_value="$1"
  local config_file="$2"

  if [[ -n "$config_value" ]]; then
    CWT_WORKTREE_DIR="$config_value"
  else
    unset CWT_WORKTREE_DIR
  fi

  _cwt_worktrees_dir="$(_cwt_resolve_worktrees_dir)"
  _cwt_validate_worktrees_dir "$_cwt_worktrees_dir" || return 1

  if _cwt_write_setup_config "$config_file" "$config_value"; then
    _cwt_log_success "Saved cwt config to $(_cwt_bold "$config_file")."
  else
    _cwt_log_warn "Using this choice for the current command only."
  fi

  _cwt_log_item "Worktree root: $(_cwt_dim "$_cwt_worktrees_dir")"
}

_cwt_should_run_setup_wizard() {
  local config_file
  config_file=$(_cwt_config_file_path)

  [[ -n "${CWT_SKIP_SETUP_WIZARD:-}" ]] && return 1
  [[ -n "${CWT_WORKTREE_DIR:-}" ]] && return 1
  [[ -f "$config_file" ]] && return 1

  [[ "${CWT_FORCE_SETUP_WIZARD:-0}" == "1" ]] && return 0
  _cwt_is_interactive
}

_cwt_maybe_run_setup_wizard() {
  local config_file
  local default_root="${_cwt_git_root}/.worktrees"
  local config_value=""
  local custom_root
  local browse_status
  local choice
  local index
  local -a option_kinds=()
  local -a option_labels=()
  local -a option_values=()
  local detected_line detected_label detected_path

  _cwt_should_run_setup_wizard || return 0

  config_file=$(_cwt_config_file_path)

  echo "" >&2
  _cwt_log_info "No cwt config found."
  _cwt_log_item "Project: $(_cwt_bold "$_cwt_git_root")"
  _cwt_log_item "Recommended worktree root: $(_cwt_dim "$default_root")"
  _cwt_log_item "Config file: $(_cwt_dim "$config_file")"

  if _cwt_confirm "Use the recommended location?" "y"; then
    _cwt_apply_setup_choice "" "$config_file" || return 1
    return 0
  fi

  while IFS='|' read -r detected_label detected_path; do
    [[ -z "$detected_label" || -z "$detected_path" ]] && continue
    option_kinds+=("detected")
    option_values+=("$detected_path")
    option_labels+=("${detected_label}: ${detected_path}")
  done < <(_cwt_print_detected_worktree_roots)

  option_kinds+=("browse")
  option_values+=("")
  option_labels+=("Browse for another worktree folder")

  option_kinds+=("skip")
  option_values+=("")
  option_labels+=("Not now. Use the default for this run only")

  while true; do
    echo "" >&2
    _cwt_log_info "Okay. Choose another location."
    index=1
    for choice in "${option_labels[@]}"; do
      echo "   $(_cwt_dim "$index)") $choice" >&2
      ((index++))
    done

    choice=$(_cwt_prompt_choice "Choose another option [1]: " "1")
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#option_kinds[@]} )); then
      _cwt_log_error "Invalid selection."
      continue
    fi

    case "${option_kinds[$choice]}" in
      default)
        _cwt_apply_setup_choice "" "$config_file" || return 1
        return 0
        ;;
      detected)
        config_value=$(_cwt_worktrees_config_value "${option_values[$choice]}")
        _cwt_apply_setup_choice "$config_value" "$config_file" || return 1
        return 0
        ;;
      browse)
        custom_root=$(_cwt_browse_for_worktree_root)
        browse_status=$?
        if [[ "$browse_status" != "0" ]]; then
          continue
        fi
        config_value=$(_cwt_worktrees_config_value "$custom_root")
        _cwt_apply_setup_choice "$config_value" "$config_file" || return 1
        return 0
        ;;
      skip)
        _cwt_log_warn "Setup skipped. Using $(_cwt_bold "$default_root") for this run."
        return 0
        ;;
    esac
  done
}

_cwt_require_git() {
  local invocation_dir="${PWD:A}"

  _cwt_current_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    _cwt_log_error "Not inside a git repository. Run cwt from within a git project."
    return 1
  fi

  _cwt_current_root="${_cwt_current_root:A}"

  local git_common_dir
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ -z "$git_common_dir" ]]; then
    _cwt_git_root="$_cwt_current_root"
  else
    if [[ "$git_common_dir" != /* ]]; then
      git_common_dir="${invocation_dir}/${git_common_dir}"
    fi
    git_common_dir="${git_common_dir:A}"
    _cwt_git_root="${git_common_dir:h}"
  fi

  _cwt_worktrees_dir="$(_cwt_resolve_worktrees_dir)"
  _cwt_validate_worktrees_dir "$_cwt_worktrees_dir" || return 1
}

# Collect cwt-managed worktrees using git metadata instead of path globs.
# This keeps names intact even when they contain slashes (e.g. feat/aaa).
typeset -ga _cwt_worktree_names_cache=()
typeset -ga _cwt_worktree_paths_cache=()

_cwt_collect_managed_worktrees() {
  _cwt_worktree_names_cache=()
  _cwt_worktree_paths_cache=()

  [[ -d "$_cwt_worktrees_dir" ]] || return 0

  local managed_root="${_cwt_worktrees_dir:A}"
  local line wt_path name
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == worktree\ * ]] || continue

    wt_path="${line#worktree }"
    wt_path="${wt_path:A}"
    [[ "$wt_path" == "$managed_root/"* ]] || continue

    name="${wt_path#$managed_root/}"
    [[ -z "$name" ]] && continue

    _cwt_worktree_names_cache+=("$name")
    _cwt_worktree_paths_cache+=("$wt_path")
  done < <(git -C "$_cwt_git_root" worktree list --porcelain 2>/dev/null)
}

_cwt_worktree_path_from_name() {
  local target_name="$1"
  local i
  for (( i=1; i<=${#_cwt_worktree_names_cache[@]}; i++ )); do
    if [[ "${_cwt_worktree_names_cache[$i]}" == "$target_name" ]]; then
      echo "${_cwt_worktree_paths_cache[$i]}"
      return 0
    fi
  done
  return 1
}

_cwt_name_in_list() {
  local target="$1"
  shift

  local candidate
  for candidate in "$@"; do
    [[ "$candidate" == "$target" ]] && return 0
  done
  return 1
}

_cwt_select_worktree_interactive() {
  local fzf_prompt="$1"
  local list_title="$2"
  shift 2
  local -a names=("$@")

  local selected=""
  local fzf_status=1
  local i
  local num
  local name

  if command -v fzf &>/dev/null; then
    selected=$(printf '%s\n' "${names[@]}" | fzf \
      --prompt="$fzf_prompt" \
      --height=40% \
      --border \
      --header="ESC: cancel  Enter: select" 2>/dev/null)
    fzf_status=$?
    if [[ $fzf_status -ne 0 && $fzf_status -ne 130 ]]; then
      selected=""
      _cwt_log_warn "fzf failed. Falling back to numbered selection."
    fi
  fi

  if [[ -z "$selected" && $fzf_status -ne 130 ]]; then
    echo "" >&2
    _cwt_log_info "$list_title"
    i=1
    for name in "${names[@]}"; do
      echo "   $(_cwt_dim "$i)") $name" >&2
      ((i++))
    done
    echo -n "$(_cwt_cyan '?') Choice: " >&2
    read num
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#names[@]} )); then
      selected="${names[$num]}"
    else
      _cwt_log_error "Invalid selection."
      return 1
    fi
  fi

  echo "$selected"
}

_cwt_default_assistant() {
  echo "${${CWT_DEFAULT_ASSISTANT:-claude}:l}"
}

_cwt_is_valid_assistant() {
  case "${1:l}" in
    claude|codex|gemini) return 0 ;;
    *) return 1 ;;
  esac
}

_cwt_assistant_env_var_name() {
  case "${1:l}" in
    claude) echo "CWT_CMD_CLAUDE" ;;
    codex) echo "CWT_CMD_CODEX" ;;
    gemini) echo "CWT_CMD_GEMINI" ;;
  esac
}

_cwt_assistant_default_candidates() {
  case "${1:l}" in
    claude) echo "claude" ;;
    codex) echo "codex" ;;
    gemini) echo "gemini gemini-cli" ;;
  esac
}

_cwt_default_launch_target() {
  echo "${${CWT_LAUNCH_TARGET:-current}:l}"
}

_cwt_is_valid_launch_target() {
  case "${1:l}" in
    current|split|tab) return 0 ;;
    *) return 1 ;;
  esac
}

_cwt_default_permission_mode() {
  echo "${${CWT_PERMISSION_MODE:-default}:l}"
}

_cwt_is_valid_permission_mode() {
  case "${1:l}" in
    default|full) return 0 ;;
    *) return 1 ;;
  esac
}

_cwt_permission_flag_for_assistant() {
  local assistant="${1:l}"
  local mode="${2:l}"

  [[ "$mode" == "full" ]] || return 0

  case "$assistant" in
    codex) echo "--yolo" ;;
    claude) echo "--dangerously-skip-permissions" ;;
    *) echo "" ;;
  esac
}

_cwt_reset_launch_parse_state() {
  _cwt_launch_parse_assistant=$(_cwt_default_assistant)
  _cwt_launch_parse_target=$(_cwt_default_launch_target)
  _cwt_launch_parse_permission=$(_cwt_default_permission_mode)
  _cwt_launch_parse_target_explicit=0
  _cwt_launch_parse_consumed=0
  _cwt_launch_parse_requested=0
}

_cwt_parse_shared_launch_option() {
  local arg="$1"
  local next_value="$2"
  local inline_value

  _cwt_launch_parse_consumed=0
  _cwt_launch_parse_requested=0

  case "$arg" in
    --assistant)
      if [[ -z "$next_value" ]]; then
        _cwt_log_error "Missing value for $(_cwt_bold '--assistant')."
        echo "  Use one of: claude, codex, gemini" >&2
        return 1
      fi
      _cwt_launch_parse_assistant="${next_value:l}"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=2
      ;;
    --assistant=*)
      inline_value="${arg#--assistant=}"
      _cwt_launch_parse_assistant="${inline_value:l}"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --claude|--codex|--gemini)
      _cwt_launch_parse_assistant="${arg#--}"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --launch-target)
      if [[ -z "$next_value" ]]; then
        _cwt_log_error "Missing value for $(_cwt_bold '--launch-target')."
        echo "  Use one of: current, split, tab" >&2
        return 1
      fi
      _cwt_launch_parse_target="${next_value:l}"
      _cwt_launch_parse_target_explicit=1
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=2
      ;;
    --launch-target=*)
      inline_value="${arg#--launch-target=}"
      _cwt_launch_parse_target="${inline_value:l}"
      _cwt_launch_parse_target_explicit=1
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --current|--split|--tab)
      _cwt_launch_parse_target="${arg#--}"
      _cwt_launch_parse_target_explicit=1
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --all-permissions)
      _cwt_launch_parse_permission="full"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --default-permissions)
      _cwt_launch_parse_permission="default"
      _cwt_launch_parse_consumed=1
      ;;
    --yolo)
      _cwt_launch_parse_assistant="codex"
      _cwt_launch_parse_permission="full"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    --dangerously-skip-permissions)
      _cwt_launch_parse_assistant="claude"
      _cwt_launch_parse_permission="full"
      _cwt_launch_parse_requested=1
      _cwt_launch_parse_consumed=1
      ;;
    *)
      return 2
      ;;
  esac

  return 0
}

_cwt_preflight_launch_target() {
  local launch_target="${1:l}"
  local launch_target_explicit="${2:-0}"

  if [[ "$launch_target_explicit" != "1" || "$launch_target" == "current" ]]; then
    return 0
  fi

  local mux
  mux=$(_cwt_active_multiplexer)
  if [[ "$mux" == "none" ]]; then
    _cwt_log_error "Launch target '$launch_target' requires tmux or zellij."
    _cwt_log_item "Run inside tmux/zellij, or use $(_cwt_bold '--current')."
    return 1
  fi
}

_cwt_command_has_flag() {
  local flag="$1"
  shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$flag" ]] && return 0
  done
  return 1
}

_cwt_active_multiplexer() {
  if [[ -n "$TMUX" ]] && command -v tmux >/dev/null 2>&1; then
    echo "tmux"
    return 0
  fi

  if [[ -n "$ZELLIJ" ]] && command -v zellij >/dev/null 2>&1; then
    echo "zellij"
    return 0
  fi

  echo "none"
}

_cwt_shell_join_quoted() {
  local -a argv=("$@")
  echo "${(j: :)${(q)argv}}"
}

_cwt_command_exists() {
  local command_line="$1"
  local -a parts
  parts=(${(z)command_line})
  [[ ${#parts[@]} -gt 0 ]] || return 1
  command -v "${parts[1]}" >/dev/null 2>&1
}

_cwt_resolve_assistant_cmd() {
  local assistant="${1:l}"
  local env_var="$(_cwt_assistant_env_var_name "$assistant")"
  local custom_cmd="${(P)env_var}"
  local -a tried=()

  if [[ -n "$custom_cmd" ]]; then
    tried+=("$custom_cmd")
    if _cwt_command_exists "$custom_cmd"; then
      echo "$custom_cmd"
      return 0
    fi
    _cwt_log_error "Selected assistant '$assistant' is not available."
    _cwt_log_item "Tried: ${tried[*]}"
    _cwt_log_item "Install it or set ${env_var} to a valid command."
    return 1
  fi

  local candidates_text
  candidates_text=$(_cwt_assistant_default_candidates "$assistant")
  local -a candidates=(${=candidates_text})
  local candidate
  for candidate in "${candidates[@]}"; do
    tried+=("$candidate")
    if _cwt_command_exists "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  _cwt_log_error "Selected assistant '$assistant' is not available."
  _cwt_log_item "Tried: ${tried[*]}"
  _cwt_log_item "Install it or set ${env_var} to a valid command."
  return 1
}

_cwt_launch_assistant() {
  local assistant="${1:l}"
  local launch_target="${2:l}"
  local launch_target_explicit="${3:-0}"
  local permission_mode="${4:-default}"
  [[ -z "$launch_target" ]] && launch_target="current"
  [[ -z "$permission_mode" ]] && permission_mode="default"

  if ! _cwt_is_valid_launch_target "$launch_target"; then
    _cwt_log_error "Unknown launch target: $(_cwt_bold "$launch_target")"
    _cwt_log_info "Use one of: current split tab"
    return 1
  fi

  if ! _cwt_is_valid_permission_mode "$permission_mode"; then
    _cwt_log_error "Unknown permission mode: $(_cwt_bold "$permission_mode")"
    _cwt_log_info "Use one of: default full"
    return 1
  fi

  local command_line
  command_line=$(_cwt_resolve_assistant_cmd "$assistant") || return 1

  local -a command_parts
  command_parts=(${(z)command_line})

  local permission_flag
  permission_flag=$(_cwt_permission_flag_for_assistant "$assistant" "$permission_mode")
  if [[ -n "$permission_flag" ]] && ! _cwt_command_has_flag "$permission_flag" "${command_parts[@]}"; then
    command_parts+=("$permission_flag")
  fi

  if [[ "$permission_mode" == "full" && -z "$permission_flag" ]]; then
    _cwt_log_warn "Full-permission mode has no built-in flag for $assistant. Launching with default permissions."
  fi

  if [[ "$launch_target" != "current" ]]; then
    local mux
    mux=$(_cwt_active_multiplexer)
    if [[ "$mux" == "none" ]]; then
      if [[ "$launch_target_explicit" == "1" ]]; then
        _cwt_log_error "Launch target '$launch_target' requires tmux or zellij."
        _cwt_log_item "Run inside tmux/zellij, or use $(_cwt_bold '--current')."
        return 1
      fi
      _cwt_log_warn "No tmux/zellij session detected. Launching in current shell."
    else
      local target_label="$launch_target"
      [[ "$mux" == "tmux" && "$launch_target" == "tab" ]] && target_label="window"

      local command_text
      command_text=$(_cwt_shell_join_quoted "${command_parts[@]}")

      _cwt_log_info "Launching $(_cwt_bold "$assistant") in $(_cwt_bold "$mux") $(_cwt_bold "$target_label")..."
      case "$mux:$launch_target" in
        tmux:split)
          tmux split-window -c "$PWD" "$command_text"
          ;;
        tmux:tab)
          tmux new-window -c "$PWD" "$command_text"
          ;;
        zellij:split)
          zellij action new-pane -d right --cwd "$PWD" -- "${command_parts[@]}"
          ;;
        zellij:tab)
          local tab_name="cwt-${assistant}-${EPOCHSECONDS}"
          zellij action go-to-tab-name "$tab_name" --create >/dev/null 2>&1 || \
            zellij action new-tab --name "$tab_name" --cwd "$PWD"
          zellij action new-pane --cwd "$PWD" -- "${command_parts[@]}"
          ;;
        *)
          _cwt_log_error "Unsupported launch mode for environment."
          return 1
          ;;
      esac

      local mux_status=$?
      if [[ $mux_status -ne 0 ]]; then
        _cwt_log_error "Failed to launch $assistant in $mux $target_label."
        return $mux_status
      fi
      _cwt_log_success "Opened $(_cwt_bold "$assistant") in $(_cwt_bold "$mux") $(_cwt_bold "$target_label")."
      return 0
    fi
  fi

  _cwt_log_info "Launching $(_cwt_bold "$assistant")..."
  "${command_parts[@]}"
  local launch_status=$?
  if [[ $launch_status -ne 0 ]]; then
    _cwt_log_error "Assistant '$assistant' exited with code $launch_status."
    return $launch_status
  fi
}

_cwt_ensure_default_worktree_ignored() {
  [[ -n "$CWT_WORKTREE_DIR" ]] && return 0

  local gitignore_path="${_cwt_git_root}/.gitignore"
  local ignore_entry=".worktrees/"

  if [[ -f "$gitignore_path" ]] && grep -Eq '^[[:space:]]*\.worktrees/?[[:space:]]*$' "$gitignore_path"; then
    return 0
  fi

  if [[ ! -f "$gitignore_path" ]]; then
    printf "%s\n" "$ignore_entry" > "$gitignore_path" || {
      _cwt_log_error "Failed to write $(_cwt_bold '.gitignore'). Add $(_cwt_bold "$ignore_entry") manually."
      return 1
    }
    _cwt_log_info "Added $(_cwt_bold "$ignore_entry") to .gitignore."
    return 0
  fi

  if [[ -s "$gitignore_path" ]]; then
    local last_char
    last_char=$(tail -c 1 "$gitignore_path" 2>/dev/null || true)
    if [[ "$last_char" != $'\n' ]]; then
      printf '\n' >> "$gitignore_path" || {
        _cwt_log_error "Failed to write $(_cwt_bold '.gitignore'). Add $(_cwt_bold "$ignore_entry") manually."
        return 1
      }
    fi
  fi

  printf "%s\n" "$ignore_entry" >> "$gitignore_path" || {
    _cwt_log_error "Failed to write $(_cwt_bold '.gitignore'). Add $(_cwt_bold "$ignore_entry") manually."
    return 1
  }
  _cwt_log_info "Added $(_cwt_bold "$ignore_entry") to .gitignore."
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt new
# ═══════════════════════════════════════════════════════════════════════════

_cwt_new() {
  local no_launch=0
  [[ "${CWT_AUTO_LAUNCH:-true}" == "false" ]] && no_launch=1
  local positional=()

  _cwt_reset_launch_parse_state

  while [[ $# -gt 0 ]]; do
    local arg="$1"
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt new') - Create a worktree

$(_cwt_bold 'USAGE')
  cwt new [options] [name] [base-branch] [branch-name]

$(_cwt_bold 'ARGUMENTS')
  name          Worktree name (prompted if omitted)
  base-branch   Branch to base off (prompted if omitted, default: HEAD)
  branch-name   New branch name (auto-generated if omitted: wt/<name>-<rand>)

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help
  --assistant      Assistant to launch ($(_cwt_bold 'claude|codex|gemini'))
  --claude         Shortcut for --assistant claude
  --codex          Shortcut for --assistant codex
  --gemini         Shortcut for --assistant gemini
  --launch-target  Launch target ($(_cwt_bold 'current|split|tab'))
  --current        Shortcut for --launch-target current
  --split          Shortcut for --launch-target split
  --tab            Shortcut for --launch-target tab ($(_cwt_dim 'tmux window / zellij tab'))
  --all-permissions  Launch with full permissions (Codex: --yolo, Claude: --dangerously-skip-permissions)
  --default-permissions  Use assistant default permission mode
  --yolo           Shortcut for $(_cwt_bold '--assistant codex --all-permissions')
  --dangerously-skip-permissions
                   Shortcut for $(_cwt_bold '--assistant claude --all-permissions')
  --no-launch      Skip assistant launch after creation

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth                              # Create worktree, pick base interactively
  cwt new fix-auth main                         # Base off main
  cwt new fix-auth main feat/auth               # Explicit branch name
  cwt new fix-auth --assistant codex            # Launch codex in the new worktree
  cwt new fix-auth --gemini                     # Launch gemini in the new worktree
  cwt new fix-auth --assistant codex --split    # Launch codex in a split pane (tmux/zellij)
  cwt new fix-auth --assistant codex --tab      # Launch codex in a new tab (tmux/zellij)
  cwt new fix-auth --assistant codex --all-permissions  # Launch codex with --yolo
  cwt new fix-auth --yolo                        # Shortcut: codex + full permissions
  cwt new fix-auth --dangerously-skip-permissions # Shortcut: claude + full permissions
  cwt new fix-auth --no-launch                  # Create without launching an assistant
EOF
        return 0
        ;;
      --no-launch)
        no_launch=1
        shift
        ;;
      -*)
        _cwt_parse_shared_launch_option "$1" "${2:-}"
        case $? in
          0)
            [[ "$_cwt_launch_parse_requested" == "1" ]] && no_launch=0
            shift "$_cwt_launch_parse_consumed"
            ;;
          1)
            return 1
            ;;
          *)
            _cwt_log_error "Unknown option for cwt new: $(_cwt_bold "$arg")"
            echo "  Run $(_cwt_bold 'cwt new --help') for usage." >&2
            return 1
            ;;
        esac
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  local assistant="$_cwt_launch_parse_assistant"
  local launch_target="$_cwt_launch_parse_target"
  local permission_mode="$_cwt_launch_parse_permission"
  local launch_target_explicit="$_cwt_launch_parse_target_explicit"

  if ! _cwt_is_valid_assistant "$assistant"; then
    _cwt_log_error "Unknown assistant: $(_cwt_bold "$assistant")"
    _cwt_log_info "Use one of: claude codex gemini"
    return 1
  fi

  if ! _cwt_is_valid_launch_target "$launch_target"; then
    _cwt_log_error "Unknown launch target: $(_cwt_bold "$launch_target")"
    _cwt_log_info "Use one of: current split tab"
    return 1
  fi

  if [[ $no_launch -eq 0 ]] && ! _cwt_is_valid_permission_mode "$permission_mode"; then
    _cwt_log_error "Unknown permission mode: $(_cwt_bold "$permission_mode")"
    _cwt_log_info "Use one of: default full"
    return 1
  fi

  # Fail fast for explicit split/tab requests before mutating repository state.
  if [[ $no_launch -eq 0 && "$launch_target_explicit" == "1" && "$launch_target" != "current" ]]; then
    _cwt_preflight_launch_target "$launch_target" "$launch_target_explicit" || return 1
  fi

  # 1) Worktree name
  local name="${positional[1]}"
  if [[ -z "$name" ]]; then
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt new <name> [base-branch] [branch-name] [--assistant <assistant>] [--launch-target <target>|--current|--split|--tab] [--all-permissions|--default-permissions|--yolo|--dangerously-skip-permissions] [--no-launch]" >&2
      return 1
    fi
    echo -n "$(_cwt_cyan '?') Worktree name: " >&2
    read name
    [[ -z "$name" ]] && { _cwt_log_error "Name is required."; return 1; }
  fi

  local worktree_path="${_cwt_worktrees_dir}/${name}"
  if [[ -d "$worktree_path" ]]; then
    _cwt_log_error "Worktree already exists: $(_cwt_bold "$name")"
    return 1
  fi

  _cwt_ensure_default_worktree_ignored || return 1

  # 2) Base branch selection
  local base_branch="${positional[2]}"
  if [[ -z "$base_branch" && -n "$CWT_DEFAULT_BASE_BRANCH" ]]; then
    base_branch="$CWT_DEFAULT_BASE_BRANCH"
  fi
  if [[ -z "$base_branch" ]]; then
    local branches=("HEAD" $(git -C "$_cwt_git_root" branch --format='%(refname:short)' 2>/dev/null))
    if ! _cwt_is_interactive; then
      base_branch="HEAD"
    else
      local fzf_status=1
      if command -v fzf &>/dev/null; then
        base_branch=$(printf '%s\n' "${branches[@]}" | fzf \
          --prompt="Base branch > " \
          --height=40% \
          --border \
          --header="ESC: cancel  Enter: select" 2>/dev/null)
        fzf_status=$?
        if [[ $fzf_status -eq 130 ]]; then
          _cwt_log_warn "Cancelled."
          return 0
        elif [[ $fzf_status -ne 0 ]]; then
          base_branch=""
          _cwt_log_warn "fzf failed. Falling back to numbered selection."
        fi
      fi

      if [[ -z "$base_branch" ]]; then
        echo "" >&2
        _cwt_log_info "Select base branch:"
        local i=1
        for b in "${branches[@]}"; do
          echo "   $(_cwt_dim "$i)") $b" >&2
          ((i++))
        done
        echo -n "$(_cwt_cyan '?') Choice $(_cwt_dim '(default: 1=HEAD)'): " >&2
        read num
        if [[ -z "$num" ]]; then
          base_branch="HEAD"
        elif [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#branches[@]} )); then
          base_branch="${branches[$num]}"
        else
          _cwt_log_error "Invalid selection."
          return 1
        fi
      fi
    fi
  fi

  # 3) Branch name (auto-generated, with collision check)
  local branch_name="${positional[3]}"
  if [[ -z "$branch_name" ]]; then
    local rand
    local attempts=0
    while (( attempts < 5 )); do
      rand=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
      branch_name="wt/${name}-${rand}"
      git -C "$_cwt_git_root" rev-parse --verify "refs/heads/$branch_name" &>/dev/null || break
      ((attempts++))
    done
    if (( attempts >= 5 )); then
      _cwt_log_error "Could not generate a unique branch name. Specify one manually."
      return 1
    fi
  fi

  # 4) Create worktree
  echo "" >&2
  if [[ -n "$CWT_WORKTREE_DIR" ]]; then
    _cwt_log_info "Using custom worktree root: $(_cwt_bold "$_cwt_worktrees_dir")"
  fi
  _cwt_log_info "Creating worktree $(_cwt_bold "$name")..."

  git -C "$_cwt_git_root" worktree add -b "$branch_name" "$worktree_path" "$base_branch" 2>&1
  if [[ $? -ne 0 ]]; then
    _cwt_log_error "Failed to create worktree."
    return 1
  fi

  _cwt_log_success "Worktree created."

  # 5) .worktreeinclude handling
  local include_file="${_cwt_git_root}/.worktreeinclude"
  if [[ -f "$include_file" ]]; then
    _cwt_log_info "Copying files from .worktreeinclude..."
    local pattern
    local trimmed_pattern
    local -a files
    local src rel dst

    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
      # Accept CRLF-formatted include files and ignore leading/trailing spaces.
      pattern="${pattern%$'\r'}"
      trimmed_pattern="${pattern#"${pattern%%[![:space:]]*}"}"
      trimmed_pattern="${trimmed_pattern%"${trimmed_pattern##*[![:space:]]}"}"

      [[ -z "$trimmed_pattern" || "$trimmed_pattern" == \#* ]] && continue

      # (N) keeps unmatched globs from throwing "no matches found".
      files=( "${_cwt_git_root}"/${~trimmed_pattern}(N) )
      if (( ${#files[@]} == 0 )); then
        if [[ "$trimmed_pattern" == *[\*\?\[]* ]]; then
          _cwt_log_warn ".worktreeinclude pattern matched nothing: $trimmed_pattern"
        fi
        continue
      fi

      for src in "${files[@]}"; do
        [[ ! -e "$src" ]] && continue
        rel="${src#${_cwt_git_root}/}"
        dst="${worktree_path}/${rel}"
        if [[ -e "$dst" || -L "$dst" ]]; then
          _cwt_log_warn ".worktreeinclude skipped existing destination: $rel"
          continue
        fi
        mkdir -p "$(dirname "$dst")" || return 1
        cp -R "$src" "$dst" || return 1
        _cwt_log_item "$rel"
      done
    done < "$include_file"
  fi

  # 6) Summary box
  {
    echo ""
    echo "  $(_cwt_dim '┌──────────────────────────────────────────────')"
    echo "  $(_cwt_dim '│') $(_cwt_green '✓') Worktree ready"
    echo "  $(_cwt_dim '│')"
    echo "  $(_cwt_dim '│')  $(_cwt_bold 'Name')     $name"
    echo "  $(_cwt_dim '│')  $(_cwt_bold 'Branch')   $branch_name"
    echo "  $(_cwt_dim '│')  $(_cwt_bold 'Base')     $base_branch"
    echo "  $(_cwt_dim '│')  $(_cwt_bold 'Path')     $(_cwt_dim "$worktree_path")"
    echo "  $(_cwt_dim '└──────────────────────────────────────────────')"
    echo ""
  } >&2

  # 7) Enter worktree and optionally launch an assistant
  pushd "$worktree_path" > /dev/null
  if [[ $no_launch -eq 0 ]]; then
    _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" "$permission_mode" || return $?
  else
    _cwt_log_success "Ready in $(_cwt_bold "$worktree_path")"
  fi
  _cwt_log_item "Run $(_cwt_bold 'popd') to return to your previous directory."
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt ls
# ═══════════════════════════════════════════════════════════════════════════

_cwt_ls() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt ls') - List worktrees

$(_cwt_bold 'USAGE')
  cwt ls [options]

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help

$(_cwt_bold 'OUTPUT')
  Shows all worktrees with branch, status, and last commit info.
  Data table goes to stdout; decoration goes to stderr.
EOF
        return 0
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt ls: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt ls --help') for usage." >&2
        return 1
        ;;
    esac
  done

  if [[ ! -d "$_cwt_worktrees_dir" ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  local count=0
  local entries=()
  _cwt_collect_managed_worktrees
  local wt_name d i

  for (( i=1; i<=${#_cwt_worktree_names_cache[@]}; i++ )); do
    wt_name="${_cwt_worktree_names_cache[$i]}"
    d="${_cwt_worktree_paths_cache[$i]}"
    [[ -z "$wt_name" || -z "$d" ]] && continue
    local branch=$(git -C "$d" branch --show-current 2>/dev/null)
    local commit_hash=$(git -C "$d" log -1 --format='%h' 2>/dev/null)
    local commit_msg=$(git -C "$d" log -1 --format='%s' 2>/dev/null)
    local commit_ts=$(git -C "$d" log -1 --format='%ct' 2>/dev/null)
    local relative_time=""
    [[ -n "$commit_ts" ]] && relative_time=$(_cwt_relative_time "$commit_ts")

    # Check dirty status (staged, unstaged, and untracked files)
    local status_label
    local has_untracked=$(git -C "$d" ls-files --others --exclude-standard 2>/dev/null | head -1)
    if git -C "$d" diff --quiet 2>/dev/null && git -C "$d" diff --cached --quiet 2>/dev/null && [[ -z "$has_untracked" ]]; then
      status_label="$(_cwt_green 'clean')"
    else
      status_label="$(_cwt_yellow 'dirty')"
    fi

    # Truncate long commit messages
    if [[ ${#commit_msg} -gt 40 ]]; then
      commit_msg="${commit_msg:0:37}..."
    fi

    entries+=("$wt_name|$branch|$status_label|$commit_hash|$commit_msg|$relative_time")
    ((count++))
  done

  if [[ $count -eq 0 ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  # Header decoration goes to stderr
  echo "" >&2
  echo "  $(_cwt_bold "$(_cwt_cyan 'Worktrees')") $(_cwt_dim "($_cwt_git_root)")" >&2
  echo "  $(_cwt_dim '─────────────────────────────────────────────────────────────────')" >&2
  echo "" >&2

  # Data table goes to stdout
  for entry in "${entries[@]}"; do
    local wt_name="${entry%%|*}"; entry="${entry#*|}"
    local branch="${entry%%|*}"; entry="${entry#*|}"
    local wt_status="${entry%%|*}"; entry="${entry#*|}"
    local hash="${entry%%|*}"; entry="${entry#*|}"
    local msg="${entry%%|*}"; entry="${entry#*|}"
    local when="$entry"

    printf "  $(_cwt_bold '%-18s') $(_cwt_blue '%-24s') %s\n" "$wt_name" "$branch" "$wt_status"
    printf "  $(_cwt_dim '%-18s') $(_cwt_dim '%s %s') $(_cwt_dim '(%s)')\n" "" "$hash" "$msg" "$when"
    echo ""
  done

  # Footer decoration goes to stderr
  echo "  $(_cwt_dim '─────────────────────────────────────────────────────────────────')" >&2
  echo "  $(_cwt_dim "Total: $count worktree(s)")" >&2
  echo "" >&2
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt rm
# ═══════════════════════════════════════════════════════════════════════════

_cwt_rm() {
  local force=0
  local positional=()

  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt rm') - Remove a worktree

$(_cwt_bold 'USAGE')
  cwt rm [options] [name]

$(_cwt_bold 'ARGUMENTS')
  name          Worktree to remove (prompted if omitted)

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help
  -f, --force      Skip confirmation prompt

$(_cwt_bold 'EXAMPLES')
  cwt rm fix-auth            # Remove with confirmation
  cwt rm -f fix-auth         # Remove without confirmation
  cwt rm                     # Interactive selection
EOF
        return 0
        ;;
      -f|--force)
        force=1
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt rm: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt rm --help') for usage." >&2
        return 1
        ;;
      *)
        positional+=("$arg")
        ;;
    esac
  done

  local selected="${positional[1]}"

  if [[ ! -d "$_cwt_worktrees_dir" ]]; then
    if [[ -n "$selected" ]]; then
      _cwt_log_error "No worktrees found. Cannot remove: $(_cwt_bold "$selected")"
      return 1
    fi
    _cwt_log_info "No worktrees to remove."
    return 0
  fi

  # Collect worktree names
  _cwt_collect_managed_worktrees
  local worktree_names=("${_cwt_worktree_names_cache[@]}")

  if [[ ${#worktree_names[@]} -eq 0 ]]; then
    if [[ -n "$selected" ]]; then
      _cwt_log_error "No worktrees found. Cannot remove: $(_cwt_bold "$selected")"
      return 1
    fi
    _cwt_log_info "No worktrees to remove."
    return 0
  fi

  if [[ -n "$selected" ]]; then
    if ! _cwt_name_in_list "$selected" "${worktree_names[@]}"; then
      _cwt_log_error "Worktree not found: $(_cwt_bold "$selected")"
      _cwt_log_info "Available: ${worktree_names[*]}"
      return 1
    fi
  else
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt rm <name> [-f|--force]" >&2
      return 1
    fi
    selected=$(_cwt_select_worktree_interactive "Remove worktree > " "Select worktree to remove:" "${worktree_names[@]}") || return 1
  fi

  [[ -z "$selected" ]] && { _cwt_log_warn "Cancelled."; return 0; }

  local worktree_path
  worktree_path=$(_cwt_worktree_path_from_name "$selected")
  if [[ -z "$worktree_path" ]]; then
    _cwt_log_error "Worktree path not found for: $(_cwt_bold "$selected")"
    return 1
  fi
  local branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null)

  # Confirm
  if [[ $force -eq 0 ]]; then
    if ! _cwt_is_interactive; then
      _cwt_log_error "Confirmation required in non-interactive mode."
      echo "  Re-run with $(_cwt_bold '--force') to remove non-interactively." >&2
      return 1
    fi
    echo "" >&2
    _cwt_log_warn "This will remove:"
    _cwt_log_item "Worktree: $(_cwt_bold "$selected")"
    [[ -n "$branch" ]] && _cwt_log_item "Branch:   $(_cwt_bold "$branch") (will be deleted)"
    _cwt_log_item "Path:     $(_cwt_dim "$worktree_path")"
    echo "" >&2
    echo -n "$(_cwt_cyan '?') Remove '$selected'? $(_cwt_dim '(y/N)'): " >&2
    read confirm
    if [[ "$confirm" != [yY] ]]; then
      _cwt_log_warn "Cancelled."
      return 0
    fi
  fi

  # Remove worktree
  if [[ "${_cwt_current_root:A}" == "${worktree_path:A}" ]]; then
    cd "$_cwt_git_root" || {
      _cwt_log_error "Failed to move to main repository before removal."
      return 1
    }
    _cwt_log_info "Moved to main repository: $(_cwt_dim "$_cwt_git_root")"
  fi

  _cwt_log_info "Removing worktree $(_cwt_bold "$selected")..."

  local rm_output
  rm_output=$(git -C "$_cwt_git_root" worktree remove "$worktree_path" 2>&1)
  if [[ $? -ne 0 ]]; then
    if [[ $force -eq 1 ]]; then
      git -C "$_cwt_git_root" worktree remove --force "$worktree_path" 2>&1
      if [[ $? -ne 0 ]]; then
        _cwt_log_error "Failed to remove worktree."
        return 1
      fi
    else
      _cwt_log_warn "Worktree has uncommitted changes."
      echo -n "$(_cwt_cyan '?') Force remove anyway? $(_cwt_dim '(y/N)'): " >&2
      read force_confirm
      if [[ "$force_confirm" == [yY] ]]; then
        git -C "$_cwt_git_root" worktree remove --force "$worktree_path" 2>&1
        if [[ $? -ne 0 ]]; then
          _cwt_log_error "Failed to force remove worktree."
          return 1
        fi
      else
        _cwt_log_warn "Cancelled. Commit or stash your changes first."
        return 0
      fi
    fi
  fi

  # Safe branch cleanup: try -d first, ask before -D
  if [[ -n "$branch" ]]; then
    local branch_err
    branch_err=$(git -C "$_cwt_git_root" branch -d "$branch" 2>&1)
    if [[ $? -eq 0 ]]; then
      _cwt_log_success "Branch $(_cwt_bold "$branch") deleted."
    elif [[ $force -eq 1 ]]; then
      git -C "$_cwt_git_root" branch -D "$branch" 2>/dev/null && \
        _cwt_log_success "Branch $(_cwt_bold "$branch") force-deleted."
    else
      _cwt_log_warn "Branch $(_cwt_bold "$branch") has unmerged commits."
      echo -n "$(_cwt_cyan '?') Force delete branch? $(_cwt_dim '(y/N)'): " >&2
      read branch_confirm
      if [[ "$branch_confirm" == [yY] ]]; then
        git -C "$_cwt_git_root" branch -D "$branch" 2>/dev/null && \
          _cwt_log_success "Branch $(_cwt_bold "$branch") force-deleted."
      else
        _cwt_log_info "Branch $(_cwt_bold "$branch") kept."
      fi
    fi
  fi

  _cwt_log_success "Worktree $(_cwt_bold "$selected") removed."
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt cd
# ═══════════════════════════════════════════════════════════════════════════

_cwt_cd() {
  local launch_assistant=0
  local positional=()

  _cwt_reset_launch_parse_state

  while [[ $# -gt 0 ]]; do
    local arg="$1"
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt cd') - Enter an existing worktree

$(_cwt_bold 'USAGE')
  cwt cd [name]

$(_cwt_bold 'ARGUMENTS')
  name    Worktree to enter (prompted if omitted)

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help
  --assistant      Assistant to launch ($(_cwt_bold 'claude|codex|gemini'))
  --claude         Shortcut for --assistant claude
  --codex          Shortcut for --assistant codex
  --gemini         Shortcut for --assistant gemini
  --launch-target  Launch target ($(_cwt_bold 'current|split|tab'))
  --current        Shortcut for --launch-target current
  --split          Shortcut for --launch-target split
  --tab            Shortcut for --launch-target tab ($(_cwt_dim 'tmux window / zellij tab'))
  --all-permissions  Launch with full permissions (Codex: --yolo, Claude: --dangerously-skip-permissions)
  --default-permissions  Use assistant default permission mode
  --yolo           Shortcut for $(_cwt_bold '--assistant codex --all-permissions')
  --dangerously-skip-permissions
                   Shortcut for $(_cwt_bold '--assistant claude --all-permissions')

$(_cwt_bold 'EXAMPLES')
  cwt cd fix-auth                       # Enter worktree directory
  cwt cd fix-auth --assistant codex     # Enter and launch codex
  cwt cd fix-auth --gemini              # Enter and launch gemini
  cwt cd fix-auth --assistant codex --split
  cwt cd fix-auth --assistant codex --tab
  cwt cd fix-auth --assistant codex --all-permissions
  cwt cd fix-auth --yolo
  cwt cd fix-auth --dangerously-skip-permissions
  cwt cd                                # Main repo: interactive selection, worktree: return to main
EOF
        return 0 ;;
      -*)
        _cwt_parse_shared_launch_option "$1" "${2:-}"
        case $? in
          0)
            [[ "$_cwt_launch_parse_requested" == "1" ]] && launch_assistant=1
            shift "$_cwt_launch_parse_consumed"
            ;;
          1)
            return 1
            ;;
          *)
            _cwt_log_error "Unknown option for cwt cd: $(_cwt_bold "$arg")"
            echo "  Run $(_cwt_bold 'cwt cd --help') for usage." >&2
            return 1
            ;;
        esac
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  local assistant="$_cwt_launch_parse_assistant"
  local launch_target="$_cwt_launch_parse_target"
  local permission_mode="$_cwt_launch_parse_permission"
  local launch_target_explicit="$_cwt_launch_parse_target_explicit"

  if [[ $launch_assistant -eq 1 ]] && ! _cwt_is_valid_assistant "$assistant"; then
    _cwt_log_error "Unknown assistant: $(_cwt_bold "$assistant")"
    _cwt_log_info "Use one of: claude codex gemini"
    return 1
  fi

  if [[ $launch_assistant -eq 1 ]] && ! _cwt_is_valid_launch_target "$launch_target"; then
    _cwt_log_error "Unknown launch target: $(_cwt_bold "$launch_target")"
    _cwt_log_info "Use one of: current split tab"
    return 1
  fi

  if [[ $launch_assistant -eq 1 ]] && ! _cwt_is_valid_permission_mode "$permission_mode"; then
    _cwt_log_error "Unknown permission mode: $(_cwt_bold "$permission_mode")"
    _cwt_log_info "Use one of: default full"
    return 1
  fi

  if [[ $launch_assistant -eq 1 && "$launch_target_explicit" == "1" && "$launch_target" != "current" ]]; then
    _cwt_preflight_launch_target "$launch_target" "$launch_target_explicit" || return 1
  fi

  local selected="${positional[1]}"
  local main_root="${_cwt_git_root:A}"
  local current_root="${_cwt_current_root:A}"

  # When run inside a worktree with no name, return to the main repository.
  if [[ -z "$selected" && "$current_root" != "$main_root" ]]; then
    cd "$_cwt_git_root" || {
      _cwt_log_error "Failed to enter main repository."
      return 1
    }

    _cwt_log_success "Entered main repository"
    _cwt_log_item "$(_cwt_dim "$_cwt_git_root")"

    if [[ -d "$_cwt_worktrees_dir" ]]; then
      local recommendations=()
      _cwt_collect_managed_worktrees
      local d n i
      for (( i=1; i<=${#_cwt_worktree_names_cache[@]}; i++ )); do
        n="${_cwt_worktree_names_cache[$i]}"
        d="${_cwt_worktree_paths_cache[$i]}"
        [[ -z "$n" || -z "$d" ]] && continue
        [[ "${d:A}" == "$current_root" ]] && continue
        recommendations+=("$n")
      done
      if [[ ${#recommendations[@]} -gt 0 ]]; then
        _cwt_log_info "You can enter: ${recommendations[*]}"
        _cwt_log_item "Run $(_cwt_bold 'cwt cd <name>') to jump to another worktree."
      fi
    fi

    if [[ $launch_assistant -eq 1 ]]; then
      _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" "$permission_mode" || return $?
    fi

    return 0
  fi

  if [[ ! -d "$_cwt_worktrees_dir" ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  # Collect names
  _cwt_collect_managed_worktrees
  local names=("${_cwt_worktree_names_cache[@]}")

  if [[ ${#names[@]} -eq 0 ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  if [[ -n "$selected" ]]; then
    if ! _cwt_name_in_list "$selected" "${names[@]}"; then
      _cwt_log_error "Not found: $(_cwt_bold "$selected")"
      _cwt_log_info "Available: ${names[*]}"
      return 1
    fi
  else
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt cd <name> [--assistant <assistant>|--claude|--codex|--gemini] [--launch-target <target>|--current|--split|--tab] [--all-permissions|--default-permissions|--yolo|--dangerously-skip-permissions]" >&2
      return 1
    fi
    selected=$(_cwt_select_worktree_interactive "Enter worktree > " "Select worktree:" "${names[@]}") || return 1
  fi

  [[ -z "$selected" ]] && { _cwt_log_warn "Cancelled."; return 0; }

  local wt_path
  wt_path=$(_cwt_worktree_path_from_name "$selected")
  if [[ -z "$wt_path" ]]; then
    _cwt_log_error "Worktree path not found: $(_cwt_bold "$selected")"
    return 1
  fi
  pushd "$wt_path" > /dev/null
  _cwt_log_success "Entered $(_cwt_bold "$selected")"

  if [[ $launch_assistant -eq 1 ]]; then
    _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" "$permission_mode" || return $?
  fi

  _cwt_log_item "Run $(_cwt_bold 'popd') to return to your previous directory."
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt update
# ═══════════════════════════════════════════════════════════════════════════

_cwt_log_update_result() {
  local old_version="$1"
  local new_version="$2"
  local old_commit="$3"
  local new_commit="$4"

  if [[ -n "$old_commit" && -n "$new_commit" ]]; then
    if [[ "$old_commit" == "$new_commit" ]]; then
      _cwt_log_success "Already up to date (v${new_version})."
      return
    fi

    if [[ "$old_version" == "$new_version" ]]; then
      _cwt_log_success "Updated cwt to latest commit (v${new_version})."
      return
    fi

    _cwt_log_success "Updated cwt: $old_version -> $new_version"
    return
  fi

  if [[ "$old_version" == "$new_version" ]]; then
    _cwt_log_success "Already up to date (v${new_version})."
  else
    _cwt_log_success "Updated cwt: $old_version -> $new_version"
  fi
}

_cwt_update() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt update') - Self-update cwt

$(_cwt_bold 'USAGE')
  cwt update [options]

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help

$(_cwt_bold 'DESCRIPTION')
  Pulls the latest version from git and re-sources cwt.sh.
  Requires cwt to be installed from a git checkout.
EOF
        return 0
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt update: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt update --help') for usage." >&2
        return 1
        ;;
    esac
  done

  local cwt_dir="${CWT_DIR:-$HOME/.cwt}"
  local cwt_file="$cwt_dir/cwt.sh"
  if ! git -C "$cwt_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _cwt_log_error "cwt update requires a git-based install. Cannot update."
    return 1
  fi

  if [[ ! -f "$cwt_file" ]]; then
    _cwt_log_error "Update failed. Missing cwt.sh in $(_cwt_bold "$cwt_dir")."
    return 1
  fi

  local old_version="$CWT_VERSION"
  local old_commit new_commit pull_output
  old_commit=$(git -C "$cwt_dir" rev-parse --verify HEAD 2>/dev/null || true)
  _cwt_log_info "Checking for updates..."

  if ! pull_output=$(git -C "$cwt_dir" pull --ff-only 2>&1); then
    _cwt_log_error "Update failed. See git output below."
    _cwt_log_item "$pull_output"
    return 1
  fi

  # Re-source to get new version
  if ! source "$cwt_file"; then
    _cwt_log_error "Update applied, but failed to reload cwt.sh."
    _cwt_log_item "Run: source \"$cwt_file\""
    return 1
  fi
  new_commit=$(git -C "$cwt_dir" rev-parse --verify HEAD 2>/dev/null || true)

  _cwt_log_update_result "$old_version" "$CWT_VERSION" "$old_commit" "$new_commit"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main entry point: cwt
# ═══════════════════════════════════════════════════════════════════════════

cwt() {
  _cwt_load_config
  local CWT_QUIET=0

  # Parse global flags before subcommand dispatch
  while [[ "$1" == -* ]]; do
    case "$1" in
      -q|--quiet)
        CWT_QUIET=1
        shift
        ;;
      -h|--help)
        cat <<EOF
$(_cwt_bold 'cwt') $(_cwt_dim "v${CWT_VERSION}") - AI Worktree Manager

$(_cwt_bold 'USAGE')
  cwt [global-options] <command> [options]

$(_cwt_bold 'COMMANDS')
  new      Create a new worktree and launch an assistant
  ls       List all worktrees with status
  cd       Enter an existing worktree
  rm       Remove a worktree
  update   Self-update cwt

$(_cwt_bold 'GLOBAL OPTIONS')
  -q, --quiet      Suppress informational messages
  -h, --help       Show this help
  -v, --version    Show version

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth                          # Create worktree "fix-auth"
  cwt new fix-auth main                     # Create based on main branch
  cwt new fix-auth --assistant codex        # Launch codex after create
  cwt new fix-auth --assistant codex --split  # Launch codex in tmux/zellij split
  cwt new fix-auth --no-launch              # Create without launch
  cwt ls                                    # List all worktrees
  cwt cd fix-auth                           # Enter existing worktree
  cwt cd fix-auth --assistant gemini        # Enter and launch gemini
  cwt cd fix-auth --assistant gemini --tab  # Launch gemini in tmux/zellij tab
  cwt rm fix-auth                           # Remove worktree "fix-auth"
  cwt rm -f fix-auth                        # Force remove (skip confirmation)
  cwt update                                # Update cwt to latest version
  cwt -q new fix-auth main                  # Create worktree quietly

$(_cwt_bold 'DEPENDENCIES')
  Required: git, zsh
  Optional: fzf $(_cwt_dim '(interactive branch/worktree selection)')
            claude/codex/gemini $(_cwt_dim '(assistant launch)')
            tmux/zellij $(_cwt_dim '(split/tab assistant launch target)')
EOF
        return 0
        ;;
      -v|--version)
        echo "cwt $CWT_VERSION"
        return 0
        ;;
      *)
        _cwt_log_error "Unknown option: $(_cwt_bold "$1")"
        echo "  Run $(_cwt_bold 'cwt --help') for usage." >&2
        return 1
        ;;
    esac
  done

  local subcmd="$1"

  case "$subcmd" in
    "")
      if git rev-parse --show-toplevel >/dev/null 2>&1; then
        _cwt_require_git || return 1
        if _cwt_should_run_setup_wizard; then
          _cwt_maybe_run_setup_wizard || return 1
          return 0
        fi
      fi

      cat <<EOF
$(_cwt_bold 'cwt') $(_cwt_dim "v${CWT_VERSION}") - AI Worktree Manager

$(_cwt_bold 'USAGE')
  cwt [global-options] <command> [options]

$(_cwt_bold 'COMMANDS')
  new      Create a new worktree and launch an assistant
  ls       List all worktrees with status
  cd       Enter an existing worktree
  rm       Remove a worktree
  update   Self-update cwt

$(_cwt_bold 'GLOBAL OPTIONS')
  -q, --quiet      Suppress informational messages
  -h, --help       Show this help
  -v, --version    Show version

Run $(_cwt_bold 'cwt <command> --help') for command-specific help.
EOF
      return 0
      ;;
    update)
      shift
      _cwt_update "$@"
      ;;
    new|ls|cd|rm)
      _cwt_require_git || return 1
      _cwt_maybe_run_setup_wizard || return 1
      shift
      "_cwt_${subcmd}" "$@"
      ;;
    *)
      _cwt_log_error "Unknown command: $(_cwt_bold "$subcmd")"
      echo "  Run $(_cwt_bold 'cwt --help') for usage." >&2
      return 1
      ;;
  esac
}
