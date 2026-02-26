#!/bin/sh
# cwt installer
# Usage: curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
set -e

# ── Colors ─────────────────────────────────────────────────────────
RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); CYAN=$(printf '\033[0;36m')
BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); NC=$(printf '\033[0m')

info()    { printf " %s→%s %s\n" "$CYAN" "$NC" "$*"; }
ok()      { printf " %s✓%s %s\n" "$GREEN" "$NC" "$*"; }
err()     { printf " %s✗%s %s\n" "$RED" "$NC" "$*" >&2; }

# ── Config ─────────────────────────────────────────────────────────
CWT_DIR="${CWT_DIR:-$HOME/.cwt}"
REPO="https://github.com/IamGroooooot/cwt.git"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
# shellcheck disable=SC2016 # Single quotes are intentional — appended literally to .zshrc
FPATH_LINE='fpath=("$HOME/.cwt/completions" $fpath)'
# shellcheck disable=SC2016
SOURCE_LINE='[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"'
COMPINIT_LINE='autoload -Uz compinit && compinit'

# ── Parse flags ───────────────────────────────────────────────────
AUTO_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=1 ;;
  esac
done

# ── Preflight ──────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || { err "git is required. Install: apt install git / brew install git"; exit 1; }
command -v zsh >/dev/null 2>&1 || { err "zsh is required. Install: apt install zsh / brew install zsh"; exit 1; }

# ── Install ────────────────────────────────────────────────────────
echo ""
printf " %scwt%s %sinstaller%s\n" "$BOLD" "$NC" "$DIM" "$NC"
echo ""

# Preview what will be done and confirm if stdin is a terminal
if [ -t 0 ] && [ "$AUTO_YES" -eq 0 ]; then
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
    n*|N*) echo ""; info "Cancelled."; exit 0 ;;
  esac
  echo ""
fi

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
touch "$ZSHRC" 2>/dev/null || true
if grep -qF '.cwt/cwt.sh' "$ZSHRC" 2>/dev/null; then
  info "Already configured in ${DIM}${ZSHRC}${NC}"
else
  {
    printf '\n# cwt - AI Worktree Manager\n'
    printf '%s\n' "$FPATH_LINE"
    printf '%s\n' "$SOURCE_LINE"
  } >> "$ZSHRC"
  ok "Added to ${ZSHRC}"
fi

# Ensure compinit is present
if ! grep -qF 'compinit' "$ZSHRC" 2>/dev/null; then
  printf '%s\n' "$COMPINIT_LINE" >> "$ZSHRC"
  ok "Added compinit to ${ZSHRC}"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
ok "cwt installed successfully!"
echo ""
info "Restart your shell or run:"
printf "   %ssource %s%s\n" "$BOLD" "$ZSHRC" "$NC"
echo ""
