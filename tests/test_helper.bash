# test_helper.bash — Common setup for cwt BATS tests
#
# Provides:
#   - Temp directory isolation (TEST_TMPDIR)
#   - Mock git repo creation (create_test_repo)
#   - Helper to run cwt functions in zsh (run_cwt)
#   - NO_COLOR=1 for predictable output

export NO_COLOR=1

# Path to the real cwt.sh (resolved once)
CWT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cwt.sh"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR"
  export XDG_CONFIG_HOME="$TEST_TMPDIR/.config"
}

teardown() {
  if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
    # Clean up any git worktrees before removing the temp dir
    # to avoid git lock issues
    local git_dir
    for git_dir in "$TEST_TMPDIR"/*/; do
      if [[ -d "${git_dir}.git" ]]; then
        git -C "$git_dir" worktree prune 2>/dev/null || true
      fi
    done
    rm -rf "$TEST_TMPDIR"
  fi
}

# Create a bare-bones git repo at $TEST_TMPDIR/repo with an initial commit.
# Sets REPO_DIR to the created path.
create_test_repo() {
  REPO_DIR="$TEST_TMPDIR/repo"
  mkdir -p "$REPO_DIR"
  git -C "$REPO_DIR" init -b main --quiet
  git -C "$REPO_DIR" config user.email "test@test.com"
  git -C "$REPO_DIR" config user.name "Test"
  echo "init" > "$REPO_DIR/file.txt"
  git -C "$REPO_DIR" add file.txt
  git -C "$REPO_DIR" commit -m "initial commit" --quiet
}

# Run a cwt function inside zsh.
# Usage: run_cwt <function> [args...]
# Example: run_cwt cwt new --no-claude my-wt HEAD
#
# This sources cwt.sh in a zsh subshell and calls the given function.
# stdout+stderr are captured, and the exit code is returned.
run_cwt() {
  local func="$1"
  shift
  # Build a zsh command that sources cwt.sh and calls the function
  # We pass args via positional parameters to avoid quoting issues
  local args_str=""
  for arg in "$@"; do
    args_str+=" $(printf '%q' "$arg")"
  done

  run zsh -c "
    export NO_COLOR=1
    source '$CWT_SH'
    $func$args_str
  "
}

# Run a cwt function inside a specific directory (cd first).
# Usage: run_cwt_in <dir> <function> [args...]
run_cwt_in() {
  local dir="$1"
  local func="$2"
  shift 2
  local args_str=""
  for arg in "$@"; do
    args_str+=" $(printf '%q' "$arg")"
  done

  run zsh -c "
    export NO_COLOR=1
    cd '$dir'
    source '$CWT_SH'
    $func$args_str
  "
}
