#!/usr/bin/env zsh
# shellcheck disable=SC1009,SC1036,SC1058,SC1072,SC1073
# ↑ zsh glob qualifiers like (N) and ${var:t} can't be parsed by ShellCheck
# ─────────────────────────────────────────────────────────────────────────────
# cwt - Claude Worktree Manager
# Manage git worktrees for parallel Claude Code sessions.
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
  _cwt_git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    _cwt_log_error "Not inside a git repository. Run cwt from within a git project."
    return 1
  fi
  _cwt_worktrees_dir="${CWT_WORKTREE_DIR:-${_cwt_git_root}/.claude/worktrees}"
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt new
# ═══════════════════════════════════════════════════════════════════════════

_cwt_new() {
  local no_claude=0
  [[ "$CWT_AUTO_CLAUDE" == "false" ]] && no_claude=1
  local positional=()

  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        cat <<EOF
$(_cwt_bold 'cwt new') - Create a Claude worktree

$(_cwt_bold 'USAGE')
  cwt new [options] [name] [base-branch] [branch-name]

$(_cwt_bold 'ARGUMENTS')
  name          Worktree name (prompted if omitted)
  base-branch   Branch to base off (prompted if omitted, default: HEAD)
  branch-name   New branch name (auto-generated if omitted: wt/<name>-<rand>)

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help
  --no-claude      Skip launching Claude Code after creation

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth                    # Create worktree, pick base interactively
  cwt new fix-auth main               # Base off main
  cwt new fix-auth main feat/auth     # Explicit branch name
  cwt new --no-claude my-task         # Create without launching Claude
EOF
        return 0
        ;;
      --no-claude)
        no_claude=1
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt new: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt new --help') for usage." >&2
        return 1
        ;;
      *)
        positional+=("$arg")
        ;;
    esac
  done

  # 1) Worktree name
  local name="${positional[1]}"
  if [[ -z "$name" ]]; then
    if ! _cwt_is_interactive; then
      _cwt_log_error "Worktree name is required in non-interactive mode."
      echo "  Usage: cwt new <name> [base-branch] [branch-name] [--no-claude]" >&2
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

  # 2) Base branch selection
  local base_branch="${positional[2]}"
  if [[ -z "$base_branch" && -n "$CWT_DEFAULT_BASE_BRANCH" ]]; then
    base_branch="$CWT_DEFAULT_BASE_BRANCH"
  fi
  if [[ -z "$base_branch" ]]; then
    local branches=("HEAD" $(git -C "$_cwt_git_root" branch --format='%(refname:short)' 2>/dev/null))
    if ! _cwt_is_interactive; then
      base_branch="HEAD"
    elif command -v fzf &>/dev/null; then
      base_branch=$(printf '%s\n' "${branches[@]}" | fzf \
        --prompt="Base branch > " \
        --height=40% \
        --border \
        --header="ESC: cancel  Enter: select")
      [[ -z "$base_branch" ]] && { _cwt_log_warn "Cancelled."; return 0; }
    else
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

  # 7) Enter worktree and optionally launch Claude
  pushd "$worktree_path" > /dev/null
  if [[ $no_claude -eq 0 ]]; then
    _cwt_log_info "Launching Claude Code..."
    claude
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
$(_cwt_bold 'cwt ls') - List Claude worktrees

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
    _cwt_log_info "No worktrees found."
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
    _cwt_log_info "No worktrees found."
    return 0
  fi

  # Header decoration goes to stderr
  echo "" >&2
  echo "  $(_cwt_bold "$(_cwt_cyan 'Claude Worktrees')") $(_cwt_dim "($_cwt_git_root)")" >&2
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
$(_cwt_bold 'cwt rm') - Remove a Claude worktree

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

  if [[ ! -d "$_cwt_worktrees_dir" ]]; then
    _cwt_log_error "No worktrees directory found."
    return 1
  fi

  # Collect worktree names
  local worktree_names=()
  for d in "${_cwt_worktrees_dir}"/*/(N); do
    [[ -d "$d" ]] && worktree_names+=("${d:t}")
  done

  if [[ ${#worktree_names[@]} -eq 0 ]]; then
    _cwt_log_info "No worktrees to remove."
    return 0
  fi

  # Select worktree
  local selected="${positional[1]}"

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
    if command -v fzf &>/dev/null; then
      selected=$(printf '%s\n' "${worktree_names[@]}" | fzf \
        --prompt="Remove worktree > " \
        --height=40% \
        --border \
        --header="ESC: cancel  Enter: select")
    else
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
  _cwt_log_info "Removing worktree $(_cwt_bold "$selected")..."

  local rm_output
  rm_output=$(git worktree remove "$worktree_path" 2>&1)
  if [[ $? -ne 0 ]]; then
    if [[ $force -eq 1 ]]; then
      git worktree remove --force "$worktree_path" 2>&1
      if [[ $? -ne 0 ]]; then
        _cwt_log_error "Failed to remove worktree."
        return 1
      fi
    else
      _cwt_log_warn "Worktree has uncommitted changes."
      echo -n "$(_cwt_cyan '?') Force remove anyway? $(_cwt_dim '(y/N)'): " >&2
      read force_confirm
      if [[ "$force_confirm" == [yY] ]]; then
        git worktree remove --force "$worktree_path" 2>&1
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
  local launch_claude=0
  local positional=()

  for arg in "$@"; do
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
  --claude         Also launch Claude Code

$(_cwt_bold 'EXAMPLES')
  cwt cd fix-auth            # Enter worktree directory
  cwt cd fix-auth --claude   # Enter and launch Claude
  cwt cd                     # Interactive selection
EOF
        return 0 ;;
      --claude)
        launch_claude=1
        ;;
      -*)
        _cwt_log_error "Unknown option for cwt cd: $(_cwt_bold "$arg")"
        echo "  Run $(_cwt_bold 'cwt cd --help') for usage." >&2
        return 1
        ;;
      *)
        positional+=("$arg")
        ;;
    esac
  done

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

  local selected="${positional[1]}"

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
      echo "  Usage: cwt cd <name> [--claude]" >&2
      return 1
    fi
    if command -v fzf &>/dev/null; then
      selected=$(printf '%s\n' "${names[@]}" | fzf \
        --prompt="Enter worktree > " \
        --height=40% --border \
        --header="ESC: cancel  Enter: select")
    else
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

  if [[ $launch_claude -eq 1 ]]; then
    _cwt_log_info "Launching Claude Code..."
    claude
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
$(_cwt_bold 'cwt') $(_cwt_dim "v${CWT_VERSION}") - Claude Worktree Manager

$(_cwt_bold 'USAGE')
  cwt [global-options] <command> [options]

$(_cwt_bold 'COMMANDS')
  new      Create a new worktree and launch Claude Code
  ls       List all worktrees with status
  cd       Enter an existing worktree
  rm       Remove a worktree
  update   Self-update cwt

$(_cwt_bold 'GLOBAL OPTIONS')
  -q, --quiet      Suppress informational messages
  -h, --help       Show this help
  -v, --version    Show version

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth           # Create worktree "fix-auth"
  cwt new fix-auth main      # Create based on main branch
  cwt new --no-claude task   # Create without launching Claude
  cwt ls                     # List all worktrees
  cwt cd fix-auth            # Enter existing worktree
  cwt cd fix-auth --claude   # Enter and launch Claude
  cwt rm fix-auth            # Remove worktree "fix-auth"
  cwt rm -f fix-auth         # Force remove (skip confirmation)
  cwt update                 # Update cwt to latest version
  cwt -q new fix-auth main   # Create worktree quietly

$(_cwt_bold 'DEPENDENCIES')
  Required: git, zsh
  Optional: fzf $(_cwt_dim '(interactive branch/worktree selection)')
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
$(_cwt_bold 'cwt') $(_cwt_dim "v${CWT_VERSION}") - Claude Worktree Manager

$(_cwt_bold 'USAGE')
  cwt [global-options] <command> [options]

$(_cwt_bold 'COMMANDS')
  new      Create a new worktree and launch Claude Code
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
