#!/usr/bin/env bats
# Tests for cwt update

setup() {
  load test_helper
  setup
  create_test_repo
}

teardown() {
  teardown
}

_create_remote_with_version() {
  local remote_dir="$1"
  local seed_dir="$2"
  local version="$3"

  git init --bare "$remote_dir" --quiet
  git clone "$remote_dir" "$seed_dir" --quiet
  git -C "$seed_dir" config user.email "test@test.com"
  git -C "$seed_dir" config user.name "Test"
  cat > "$seed_dir/cwt.sh" <<EOF
#!/usr/bin/env zsh
CWT_VERSION="$version"
EOF
  git -C "$seed_dir" add cwt.sh
  git -C "$seed_dir" commit -m "initial cwt script" --quiet
  git -C "$seed_dir" push origin HEAD:main --quiet
  git -C "$remote_dir" symbolic-ref HEAD refs/heads/main
}

_push_remote_cwt_version() {
  local remote_dir="$1"
  local version="$2"
  local commit_msg="$3"
  local pusher_dir
  pusher_dir="$(mktemp -d "$TEST_TMPDIR/cwt-pusher.XXXXXX")"

  git clone --branch main "$remote_dir" "$pusher_dir" --quiet
  git -C "$pusher_dir" config user.email "test@test.com"
  git -C "$pusher_dir" config user.name "Test"
  cat > "$pusher_dir/cwt.sh" <<EOF
#!/usr/bin/env zsh
# $commit_msg
CWT_VERSION="$version"
EOF
  git -C "$pusher_dir" commit -am "$commit_msg" --quiet
  git -C "$pusher_dir" push origin HEAD:main --quiet
}

@test "cwt update: unknown flag returns error" {
  run zsh -c "
    export NO_COLOR=1
    cd '$REPO_DIR'
    source '$CWT_SH'
    cwt update --bogus
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option for cwt update"* ]]
  [[ "$output" == *"cwt update --help"* ]]
}

@test "cwt update: already up to date when commit is unchanged" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"

  _create_remote_with_version "$remote_dir" "$seed_dir" "0.2.0"
  git clone --branch main "$remote_dir" "$install_dir" --quiet

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    CWT_VERSION='0.2.0'
    cwt update
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already up to date (v0.2.0)."* ]]
}

@test "cwt update: reports update when commit changes but version stays same" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"

  _create_remote_with_version "$remote_dir" "$seed_dir" "0.2.0"
  git clone --branch main "$remote_dir" "$install_dir" --quiet

  _push_remote_cwt_version "$remote_dir" "0.2.0" "same version, newer commit"

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    CWT_VERSION='0.2.0'
    cwt update
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated cwt to latest commit (v0.2.0)."* ]]
  [[ "$output" != *"Already up to date"* ]]
}

@test "cwt update: reports version bump when upstream version changes" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"

  _create_remote_with_version "$remote_dir" "$seed_dir" "0.2.0"
  git clone --branch main "$remote_dir" "$install_dir" --quiet

  _push_remote_cwt_version "$remote_dir" "0.2.1" "bump version"

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    CWT_VERSION='0.2.0'
    cwt update
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated cwt: 0.2.0 -> 0.2.1"* ]]
}

@test "cwt update: supports git installs when .git is a file" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"
  local separate_git_dir="$TEST_TMPDIR/cwt-install.gitdir"

  _create_remote_with_version "$remote_dir" "$seed_dir" "0.2.0"
  git clone --separate-git-dir "$separate_git_dir" --branch main "$remote_dir" "$install_dir" --quiet
  [ -f "$install_dir/.git" ]

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    CWT_VERSION='0.2.0'
    cwt update
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already up to date (v0.2.0)."* ]]
}

@test "cwt update: missing cwt.sh fails before pulling repository" {
  local remote_dir="$TEST_TMPDIR/git-only-remote.git"
  local seed_dir="$TEST_TMPDIR/git-only-seed"
  local install_dir="$TEST_TMPDIR/git-only-install"
  local pusher_dir="$TEST_TMPDIR/git-only-pusher"
  local before_head after_head

  git init --bare "$remote_dir" --quiet

  git clone "$remote_dir" "$seed_dir" --quiet
  git -C "$seed_dir" config user.email "test@test.com"
  git -C "$seed_dir" config user.name "Test"
  echo "init" > "$seed_dir/README.md"
  git -C "$seed_dir" add README.md
  git -C "$seed_dir" commit -m "initial non-cwt repo" --quiet
  git -C "$seed_dir" push origin HEAD:main --quiet
  git -C "$remote_dir" symbolic-ref HEAD refs/heads/main

  git clone --branch main "$remote_dir" "$install_dir" --quiet
  before_head=$(git -C "$install_dir" rev-parse HEAD)

  git clone --branch main "$remote_dir" "$pusher_dir" --quiet
  git -C "$pusher_dir" config user.email "test@test.com"
  git -C "$pusher_dir" config user.name "Test"
  echo "next" >> "$pusher_dir/README.md"
  git -C "$pusher_dir" commit -am "remote change after install" --quiet
  git -C "$pusher_dir" push origin HEAD:main --quiet

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    cwt update
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing cwt.sh"* ]]

  after_head=$(git -C "$install_dir" rev-parse HEAD)
  [[ "$before_head" == "$after_head" ]]
}

@test "cwt update: fails clearly when updated cwt.sh cannot be sourced" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"
  local pusher_dir="$TEST_TMPDIR/cwt-pusher"

  _create_remote_with_version "$remote_dir" "$seed_dir" "0.2.0"
  git clone --branch main "$remote_dir" "$install_dir" --quiet

  git clone --branch main "$remote_dir" "$pusher_dir" --quiet
  git -C "$pusher_dir" config user.email "test@test.com"
  git -C "$pusher_dir" config user.name "Test"
  cat > "$pusher_dir/cwt.sh" <<'EOF'
#!/usr/bin/env zsh
CWT_VERSION="0.2.1"
if then
EOF
  git -C "$pusher_dir" commit -am "introduce syntax error" --quiet
  git -C "$pusher_dir" push origin HEAD:main --quiet

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    CWT_VERSION='0.2.0'
    cwt update
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to reload cwt.sh"* ]]
}
