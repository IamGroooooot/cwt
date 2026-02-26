#!/usr/bin/env zsh
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
#   cwt rm [name]                    Remove a worktree
#   cwt --help                       Show help
# ─────────────────────────────────────────────────────────────────────────────

CWT_VERSION="0.1.0"

# ── ANSI color utilities ────────────────────────────────────────────────────

_cwt_red()     { printf '\033[0;31m%s\033[0m' "$*"; }
_cwt_green()   { printf '\033[0;32m%s\033[0m' "$*"; }
_cwt_yellow()  { printf '\033[0;33m%s\033[0m' "$*"; }
_cwt_blue()    { printf '\033[0;34m%s\033[0m' "$*"; }
_cwt_cyan()    { printf '\033[0;36m%s\033[0m' "$*"; }
_cwt_dim()     { printf '\033[2m%s\033[0m' "$*"; }
_cwt_bold()    { printf '\033[1m%s\033[0m' "$*"; }

# ── Logging helpers ─────────────────────────────────────────────────────────

_cwt_log_success() { echo " $(_cwt_green '✓') $*"; }
_cwt_log_error()   { echo " $(_cwt_red '✗') $*" >&2; }
_cwt_log_info()    { echo " $(_cwt_cyan '→') $*"; }
_cwt_log_warn()    { echo " $(_cwt_yellow '!') $*"; }
_cwt_log_item()    { echo "   $(_cwt_dim '•') $*"; }

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
    _cwt_log_error "Not inside a git repository."
    return 1
  fi
  _cwt_worktrees_dir="${_cwt_git_root}/.claude/worktrees"
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommand: cwt new
# ═══════════════════════════════════════════════════════════════════════════

_cwt_new() {
  local no_claude=0
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
      *)
        positional+=("$arg")
        ;;
    esac
  done

  # 1) Worktree name
  local name="${positional[1]}"
  if [[ -z "$name" ]]; then
    echo -n "$(_cwt_cyan '?') Worktree name: "
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
  if [[ -z "$base_branch" ]]; then
    local branches=("HEAD" $(git -C "$_cwt_git_root" branch --format='%(refname:short)' 2>/dev/null))
    if command -v fzf &>/dev/null; then
      base_branch=$(printf '%s\n' "${branches[@]}" | fzf \
        --prompt="Base branch > " \
        --height=40% \
        --border \
        --header="ESC: cancel  Enter: select")
      [[ -z "$base_branch" ]] && { _cwt_log_warn "Cancelled."; return 0; }
    else
      echo ""
      _cwt_log_info "Select base branch:"
      local i=1
      for b in "${branches[@]}"; do
        echo "   $(_cwt_dim "$i)") $b"
        ((i++))
      done
      echo -n "$(_cwt_cyan '?') Choice $(_cwt_dim '(default: 1=HEAD)'): "
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

  # 3) Branch name (auto-generated)
  local branch_name="${positional[3]}"
  if [[ -z "$branch_name" ]]; then
    local rand=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
    branch_name="wt/${name}-${rand}"
  fi

  # 4) Create worktree
  echo ""
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
        cp "$src" "$dst"
        _cwt_log_item "$rel"
      done
    done < "$include_file"
  fi

  # 6) Summary box
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

  # 7) Launch Claude (unless --no-claude)
  if [[ $no_claude -eq 0 ]]; then
    _cwt_log_info "Launching Claude Code..."
    cd "$worktree_path" && claude
  else
    _cwt_log_info "Entering worktree directory..."
    cd "$worktree_path"
  fi
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
EOF
        return 0
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

    # Check dirty status
    local status_label
    if git -C "$d" diff --quiet 2>/dev/null && git -C "$d" diff --cached --quiet 2>/dev/null; then
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

  echo ""
  echo "  $(_cwt_bold "$(_cwt_cyan 'Claude Worktrees')") $(_cwt_dim "($_cwt_git_root)")"
  echo "  $(_cwt_dim '─────────────────────────────────────────────────────────────────')"
  echo ""

  for entry in "${entries[@]}"; do
    local wt_name="${entry%%|*}"; entry="${entry#*|}"
    local branch="${entry%%|*}"; entry="${entry#*|}"
    local status="${entry%%|*}"; entry="${entry#*|}"
    local hash="${entry%%|*}"; entry="${entry#*|}"
    local msg="${entry%%|*}"; entry="${entry#*|}"
    local when="$entry"

    printf "  $(_cwt_bold '%-18s') $(_cwt_blue '%-24s') %s\n" "$wt_name" "$branch" "$status"
    printf "  $(_cwt_dim '%-18s') $(_cwt_dim '%s %s') $(_cwt_dim '(%s)')\n" "" "$hash" "$msg" "$when"
    echo ""
  done

  echo "  $(_cwt_dim '─────────────────────────────────────────────────────────────────')"
  echo "  $(_cwt_dim "Total: $count worktree(s)")"
  echo ""
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
    # Interactive selection
    if command -v fzf &>/dev/null; then
      selected=$(printf '%s\n' "${worktree_names[@]}" | fzf \
        --prompt="Remove worktree > " \
        --height=40% \
        --border \
        --header="ESC: cancel  Enter: select")
    else
      echo ""
      _cwt_log_info "Select worktree to remove:"
      local i=1
      for wt_name in "${worktree_names[@]}"; do
        echo "   $(_cwt_dim "$i)") $wt_name"
        ((i++))
      done
      echo -n "$(_cwt_cyan '?') Choice: "
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
    echo ""
    _cwt_log_warn "This will remove:"
    _cwt_log_item "Worktree: $(_cwt_bold "$selected")"
    [[ -n "$branch" ]] && _cwt_log_item "Branch:   $(_cwt_bold "$branch")"
    _cwt_log_item "Path:     $(_cwt_dim "$worktree_path")"
    echo ""
    echo -n "$(_cwt_cyan '?') Remove '$selected'? $(_cwt_dim '(y/N)'): "
    read confirm
    if [[ "$confirm" != y && "$confirm" != Y ]]; then
      _cwt_log_warn "Cancelled."
      return 0
    fi
  fi

  # Remove
  _cwt_log_info "Removing worktree $(_cwt_bold "$selected")..."

  git worktree remove "$worktree_path" 2>&1
  if [[ $? -ne 0 ]]; then
    _cwt_log_warn "Trying force removal..."
    git worktree remove --force "$worktree_path" 2>&1
    if [[ $? -ne 0 ]]; then
      _cwt_log_error "Failed to remove worktree."
      return 1
    fi
  fi

  # Clean up the branch if it still exists
  if [[ -n "$branch" ]]; then
    git -C "$_cwt_git_root" branch -D "$branch" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      _cwt_log_success "Branch $(_cwt_bold "$branch") deleted."
    fi
  fi

  _cwt_log_success "Worktree $(_cwt_bold "$selected") removed."
}

# ═══════════════════════════════════════════════════════════════════════════
# Main entry point: cwt
# ═══════════════════════════════════════════════════════════════════════════

cwt() {
  local subcmd="$1"

  case "$subcmd" in
    --help|-h|"")
      cat <<EOF
$(_cwt_bold 'cwt') $(_cwt_dim "v${CWT_VERSION}") - Claude Worktree Manager

$(_cwt_bold 'USAGE')
  cwt <command> [options]

$(_cwt_bold 'COMMANDS')
  new    Create a new worktree and launch Claude Code
  ls     List all worktrees with status
  rm     Remove a worktree

$(_cwt_bold 'OPTIONS')
  -h, --help       Show this help
  -v, --version    Show version

$(_cwt_bold 'EXAMPLES')
  cwt new fix-auth           # Create worktree "fix-auth"
  cwt new fix-auth main      # Create based on main branch
  cwt new --no-claude task   # Create without launching Claude
  cwt ls                     # List all worktrees
  cwt rm fix-auth            # Remove worktree "fix-auth"
  cwt rm -f fix-auth         # Force remove (skip confirmation)

$(_cwt_bold 'DEPENDENCIES')
  Required: git, zsh
  Optional: fzf $(_cwt_dim '(interactive branch/worktree selection)')
EOF
      return 0
      ;;
    --version|-v)
      echo "cwt $CWT_VERSION"
      return 0
      ;;
    new|ls|rm)
      _cwt_require_git || return 1
      shift
      "_cwt_${subcmd}" "$@"
      ;;
    *)
      _cwt_log_error "Unknown command: $(_cwt_bold "$subcmd")"
      echo ""
      echo "  Run $(_cwt_bold 'cwt --help') for usage."
      return 1
      ;;
  esac
}
