#!/bin/sh
# cwt uninstaller
set -e

RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m'); NC=$(printf '\033[0m')

info() { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }

CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

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
      sed -i '' '/# cwt - Claude Worktree Manager/d' "$ZSHRC"
      sed -i '' '/\.cwt\/cwt\.sh/d' "$ZSHRC"
    else
      sed -i '/# cwt - Claude Worktree Manager/d' "$ZSHRC"
      sed -i '/\.cwt\/cwt\.sh/d' "$ZSHRC"
    fi
    ok "Removed cwt from ${ZSHRC}"
  fi
fi

echo ""
ok "cwt uninstalled."
echo ""
