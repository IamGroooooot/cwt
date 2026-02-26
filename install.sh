#!/bin/sh
# cwt installer
# Usage: curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
set -e

# ── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()    { printf " ${CYAN}→${NC} %s\n" "$*"; }
ok()      { printf " ${GREEN}✓${NC} %s\n" "$*"; }
err()     { printf " ${RED}✗${NC} %s\n" "$*" >&2; }

# ── Config ─────────────────────────────────────────────────────────
CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
REPO="https://github.com/IamGroooooot/cwt.git"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE='[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"'

# ── Preflight ──────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || { err "git is required."; exit 1; }
command -v zsh >/dev/null 2>&1 || { err "zsh is required."; exit 1; }

# ── Install ────────────────────────────────────────────────────────
echo ""
printf " ${BOLD}cwt${NC} ${DIM}installer${NC}\n"
echo ""

if [ -d "$CWT_DIR" ]; then
  info "Updating cwt..."
  git -C "$CWT_DIR" pull --quiet --ff-only 2>/dev/null || {
    info "Pull failed, re-cloning..."
    rm -rf "$CWT_DIR"
    git clone --depth 1 --quiet "$REPO" "$CWT_DIR"
  }
  ok "Updated."
else
  info "Installing cwt to ${DIM}${CWT_DIR}${NC}..."
  git clone --depth 1 --quiet "$REPO" "$CWT_DIR"
  ok "Cloned."
fi

# ── Shell integration ──────────────────────────────────────────────
if [ -f "$ZSHRC" ] && grep -qF '.cwt/cwt.sh' "$ZSHRC" 2>/dev/null; then
  info "Already configured in ${DIM}${ZSHRC}${NC}"
else
  printf '\n# cwt - Claude Worktree Manager\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  ok "Added to ${ZSHRC}"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
ok "cwt installed successfully!"
echo ""
info "Restart your shell or run:"
printf "   ${BOLD}source %s${NC}\n" "$ZSHRC"
echo ""
