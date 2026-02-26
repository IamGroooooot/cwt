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

CWT_VERSION="0.2.0"

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

_cwt_load_config() {
  local config_file="${CWT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cwt/config}"
  [[ -f "$config_file" ]] && source "$config_file"
}

_cwt_is_interactive() {
  [[ -t 0 ]]
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

_cwt_require_git() {
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
      git_common_dir="${_cwt_current_root}/${git_common_dir}"
    fi
    git_common_dir="${git_common_dir:A}"
    _cwt_git_root="${git_common_dir:h}"
  fi

  _cwt_worktrees_dir="${CWT_WORKTREE_DIR:-${_cwt_git_root}/.worktrees}"
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

  local -a candidates=(${=(_cwt_assistant_default_candidates "$assistant")})
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
  [[ -z "$launch_target" ]] && launch_target="current"

  if ! _cwt_is_valid_launch_target "$launch_target"; then
    _cwt_log_error "Unknown launch target: $(_cwt_bold "$launch_target")"
    _cwt_log_info "Use one of: current split tab"
    return 1
  fi

  local command_line
  command_line=$(_cwt_resolve_assistant_cmd "$assistant") || return 1

  local -a command_parts
  command_parts=(${(z)command_line})

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
  local assistant="$(_cwt_default_assistant)"
  local launch_target="$(_cwt_default_launch_target)"
  local launch_target_explicit=0
  local positional=()

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
  --no-launch      Skip assistant launch after creation

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth                              # Create worktree, pick base interactively
  cwt new fix-auth main                         # Base off main
  cwt new fix-auth main feat/auth               # Explicit branch name
  cwt new fix-auth --assistant codex            # Launch codex in the new worktree
  cwt new fix-auth --gemini                     # Launch gemini in the new worktree
  cwt new fix-auth --assistant codex --split    # Launch codex in a split pane (tmux/zellij)
  cwt new fix-auth --assistant codex --tab      # Launch codex in a new tab (tmux/zellij)
  cwt new fix-auth --no-launch                  # Create without launching an assistant
EOF
        return 0
        ;;
      --no-launch)
        no_launch=1
        shift
        ;;
      --assistant)
        if [[ $# -lt 2 ]]; then
          _cwt_log_error "Missing value for $(_cwt_bold '--assistant')."
          echo "  Use one of: claude, codex, gemini" >&2
          return 1
        fi
        assistant="${2:l}"
        no_launch=0
        shift 2
        ;;
      --assistant=*)
        assistant="${${arg#--assistant=}:l}"
        no_launch=0
        shift
        ;;
      --claude|--codex|--gemini)
        assistant="${arg#--}"
        no_launch=0
        shift
        ;;
      --launch-target)
        if [[ $# -lt 2 ]]; then
          _cwt_log_error "Missing value for $(_cwt_bold '--launch-target')."
          echo "  Use one of: current, split, tab" >&2
          return 1
        fi
        launch_target="${2:l}"
        launch_target_explicit=1
        no_launch=0
        shift 2
        ;;
      --launch-target=*)
        launch_target="${${arg#--launch-target=}:l}"
        launch_target_explicit=1
        no_launch=0
        shift
        ;;
      --current)
        launch_target="current"
        launch_target_explicit=1
        no_launch=0
        shift
        ;;
      --split)
        launch_target="split"
        launch_target_explicit=1
        no_launch=0
        shift
        ;;
      --tab)
        launch_target="tab"
        launch_target_explicit=1
        no_launch=0
        shift
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt new: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt new --help') for usage." >&2
        return 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

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

  # Fail fast for explicit split/tab requests before mutating repository state.
  if [[ $no_launch -eq 0 && "$launch_target_explicit" == "1" && "$launch_target" != "current" ]]; then
    local preflight_mux
    preflight_mux=$(_cwt_active_multiplexer)
    if [[ "$preflight_mux" == "none" ]]; then
      _cwt_log_error "Launch target '$launch_target' requires tmux or zellij."
      _cwt_log_item "Run inside tmux/zellij, or use $(_cwt_bold '--current')."
      return 1
    fi
  fi

  # 1) Worktree name
  local name="${positional[1]}"
  if [[ -z "$name" ]]; then
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt new <name> [base-branch] [branch-name] [--assistant <assistant>] [--launch-target <target>|--current|--split|--tab] [--no-launch]" >&2
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
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      local files=("${_cwt_git_root}"/${~pattern})
      for src in "${files[@]}"; do
        [[ ! -e "$src" ]] && continue
        local rel="${src#${_cwt_git_root}/}"
        local dst="${worktree_path}/${rel}"
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
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
    _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" || return $?
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

  for d in "${_cwt_worktrees_dir}"/*/(N); do
    [[ ! -d "$d" ]] && continue

    local wt_name="${d:t}"
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
  local worktree_names=()
  for d in "${_cwt_worktrees_dir}"/*/(N); do
    [[ -d "$d" ]] && worktree_names+=("${d:t}")
  done

  if [[ ${#worktree_names[@]} -eq 0 ]]; then
    if [[ -n "$selected" ]]; then
      _cwt_log_error "No worktrees found. Cannot remove: $(_cwt_bold "$selected")"
      return 1
    fi
    _cwt_log_info "No worktrees to remove."
    return 0
  fi

  if [[ -n "$selected" ]]; then
    # Validate that the given name exists
    local found=0
    for wt in "${worktree_names[@]}"; do
      [[ "$wt" == "$selected" ]] && found=1 && break
    done
    if [[ $found -eq 0 ]]; then
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
    # Interactive selection
    local fzf_status=1
    if command -v fzf &>/dev/null; then
      selected=$(printf '%s\n' "${worktree_names[@]}" | fzf \
        --prompt="Remove worktree > " \
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
      _cwt_log_info "Select worktree to remove:"
      local i=1
      for wt_name in "${worktree_names[@]}"; do
        echo "   $(_cwt_dim "$i)") $wt_name" >&2
        ((i++))
      done
      echo -n "$(_cwt_cyan '?') Choice: " >&2
      read num
      if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#worktree_names[@]} )); then
        selected="${worktree_names[$num]}"
      else
        _cwt_log_error "Invalid selection."
        return 1
      fi
    fi
  fi

  [[ -z "$selected" ]] && { _cwt_log_warn "Cancelled."; return 0; }

  local worktree_path="${_cwt_worktrees_dir}/${selected}"
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
  local assistant="$(_cwt_default_assistant)"
  local launch_target="$(_cwt_default_launch_target)"
  local launch_target_explicit=0
  local positional=()

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

$(_cwt_bold 'EXAMPLES')
  cwt cd fix-auth                       # Enter worktree directory
  cwt cd fix-auth --assistant codex     # Enter and launch codex
  cwt cd fix-auth --gemini              # Enter and launch gemini
  cwt cd fix-auth --assistant codex --split
  cwt cd fix-auth --assistant codex --tab
  cwt cd                                # Main repo: interactive selection, worktree: return to main
EOF
        return 0 ;;
      --assistant)
        if [[ $# -lt 2 ]]; then
          _cwt_log_error "Missing value for $(_cwt_bold '--assistant')."
          echo "  Use one of: claude, codex, gemini" >&2
          return 1
        fi
        assistant="${2:l}"
        launch_assistant=1
        shift 2
        ;;
      --assistant=*)
        assistant="${${arg#--assistant=}:l}"
        launch_assistant=1
        shift
        ;;
      --claude|--codex|--gemini)
        assistant="${arg#--}"
        launch_assistant=1
        shift
        ;;
      --launch-target)
        if [[ $# -lt 2 ]]; then
          _cwt_log_error "Missing value for $(_cwt_bold '--launch-target')."
          echo "  Use one of: current, split, tab" >&2
          return 1
        fi
        launch_target="${2:l}"
        launch_target_explicit=1
        launch_assistant=1
        shift 2
        ;;
      --launch-target=*)
        launch_target="${${arg#--launch-target=}:l}"
        launch_target_explicit=1
        launch_assistant=1
        shift
        ;;
      --current)
        launch_target="current"
        launch_target_explicit=1
        launch_assistant=1
        shift
        ;;
      --split)
        launch_target="split"
        launch_target_explicit=1
        launch_assistant=1
        shift
        ;;
      --tab)
        launch_target="tab"
        launch_target_explicit=1
        launch_assistant=1
        shift
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt cd: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt cd --help') for usage." >&2
        return 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

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
      for d in "${_cwt_worktrees_dir}"/*/(N); do
        [[ -d "$d" ]] || continue
        [[ "${d:A}" == "$current_root" ]] && continue
        recommendations+=("${d:t}")
      done
      if [[ ${#recommendations[@]} -gt 0 ]]; then
        _cwt_log_info "You can enter: ${recommendations[*]}"
        _cwt_log_item "Run $(_cwt_bold 'cwt cd <name>') to jump to another worktree."
      fi
    fi

    if [[ $launch_assistant -eq 1 ]]; then
      _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" || return $?
    fi

    return 0
  fi

  if [[ ! -d "$_cwt_worktrees_dir" ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  # Collect names
  local names=()
  for d in "${_cwt_worktrees_dir}"/*/(N); do
    [[ -d "$d" ]] && names+=("${d:t}")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    _cwt_log_info "No worktrees yet. Run $(_cwt_bold 'cwt new') to create one."
    return 0
  fi

  if [[ -n "$selected" ]]; then
    local found=0
    for n in "${names[@]}"; do [[ "$n" == "$selected" ]] && found=1 && break; done
    if [[ $found -eq 0 ]]; then
      _cwt_log_error "Not found: $(_cwt_bold "$selected")"
      _cwt_log_info "Available: ${names[*]}"
      return 1
    fi
  else
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt cd <name> [--assistant <assistant>|--claude|--codex|--gemini] [--launch-target <target>|--current|--split|--tab]" >&2
      return 1
    fi
    local fzf_status=1
    if command -v fzf &>/dev/null; then
      selected=$(printf '%s\n' "${names[@]}" | fzf \
        --prompt="Enter worktree > " \
        --height=40% --border \
        --header="ESC: cancel  Enter: select" 2>/dev/null)
      fzf_status=$?
      if [[ $fzf_status -ne 0 && $fzf_status -ne 130 ]]; then
        selected=""
        _cwt_log_warn "fzf failed. Falling back to numbered selection."
      fi
    fi

    if [[ -z "$selected" && $fzf_status -ne 130 ]]; then
      echo "" >&2
      _cwt_log_info "Select worktree:"
      local i=1
      for n in "${names[@]}"; do
        echo "   $(_cwt_dim "$i)") $n" >&2
        ((i++))
      done
      echo -n "$(_cwt_cyan '?') Choice: " >&2
      read num
      if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#names[@]} )); then
        selected="${names[$num]}"
      else
        _cwt_log_error "Invalid selection."; return 1
      fi
    fi
  fi

  [[ -z "$selected" ]] && { _cwt_log_warn "Cancelled."; return 0; }

  local wt_path="${_cwt_worktrees_dir}/${selected}"
  pushd "$wt_path" > /dev/null
  _cwt_log_success "Entered $(_cwt_bold "$selected")"

  if [[ $launch_assistant -eq 1 ]]; then
    _cwt_launch_assistant "$assistant" "$launch_target" "$launch_target_explicit" || return $?
  fi

  _cwt_log_item "Run $(_cwt_bold 'popd') to return to your previous directory."
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt update
# ═══════════════════════════════════════════════════════════════════════════

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
  Requires cwt to be installed via git clone.
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
  if [[ ! -d "$cwt_dir/.git" ]]; then
    _cwt_log_error "cwt not installed via git. Cannot update."
    return 1
  fi

  local old_version="$CWT_VERSION"
  _cwt_log_info "Checking for updates..."

  local pull_output
  pull_output=$(git -C "$cwt_dir" pull --ff-only 2>&1)
  if [[ $? -ne 0 ]]; then
    _cwt_log_error "Update failed. Check your network connection."
    _cwt_log_item "$pull_output"
    return 1
  fi

  # Re-source to get new version
  source "$cwt_dir/cwt.sh"
  if [[ "$old_version" == "$CWT_VERSION" ]]; then
    _cwt_log_success "Already up to date (v${CWT_VERSION})."
  else
    _cwt_log_success "Updated cwt: $old_version -> $CWT_VERSION"
  fi
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
