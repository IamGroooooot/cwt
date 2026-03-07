#!/bin/sh
# cwt uninstaller
set -e

RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m'); NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }

resolve_target_dir() {
  target="$1"
  if [ -z "$target" ]; then
    return 1
  fi

  if [ -d "$target" ]; then
    (
      cd "$target" 2>/dev/null && pwd -P
    )
    return $?
  fi

  target_parent=$(dirname "$target")
  target_base=$(basename "$target")
  resolved_parent=$(
    cd "$target_parent" 2>/dev/null && pwd -P
  ) || return 1

  printf '%s/%s\n' "$resolved_parent" "$target_base"
}

ensure_safe_cwt_dir() {
  resolved_cwt_dir=$(resolve_target_dir "$CWT_DIR") || {
    info "Refusing to use unsafe CWT_DIR: $CWT_DIR"
    exit 1
  }

  case "$resolved_cwt_dir" in
    /|"$HOME")
      info "Refusing to use unsafe CWT_DIR: $resolved_cwt_dir"
      exit 1
      ;;
  esac
}

CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ensure_safe_cwt_dir

echo ""

# Remove directory
if [ -d "$CWT_DIR" ]; then
  rm -rf "$CWT_DIR"
  ok "Removed ${CWT_DIR}"
else
  info "No cwt directory found."
fi

# Remove lines from .zshrc
if [ -f "$ZSHRC" ]; then
  if grep -qF '.cwt/cwt.sh' "$ZSHRC" 2>/dev/null; then
    # macOS sed requires '' after -i
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' '/# cwt - AI Worktree Manager/d' "$ZSHRC"
      sed -i '' '/# cwt - Claude Worktree Manager/d' "$ZSHRC"
      sed -i '' '/\.cwt\/cwt\.sh/d' "$ZSHRC"
    else
      sed -i '/# cwt - AI Worktree Manager/d' "$ZSHRC"
      sed -i '/# cwt - Claude Worktree Manager/d' "$ZSHRC"
      sed -i '/\.cwt\/cwt\.sh/d' "$ZSHRC"
    fi
    ok "Removed cwt from ${ZSHRC}"
  fi
fi

echo ""
ok "cwt uninstalled."
echo ""
