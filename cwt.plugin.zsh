# cwt - AI Worktree Manager
# Plugin entry point for zinit, antigen, oh-my-zsh, etc.
# shellcheck disable=all
# ↑ This file uses zsh-only syntax that ShellCheck cannot parse

0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

source "${0:h}/cwt.sh"
