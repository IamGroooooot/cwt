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

@test "cwt update: reports update when commit changes but version stays same" {
  local remote_dir="$TEST_TMPDIR/cwt-remote.git"
  local seed_dir="$TEST_TMPDIR/cwt-seed"
  local install_dir="$TEST_TMPDIR/cwt-install"
  local pusher_dir="$TEST_TMPDIR/cwt-pusher"

  git init --bare "$remote_dir" --quiet

  git clone "$remote_dir" "$seed_dir" --quiet
  git -C "$seed_dir" config user.email "test@test.com"
  git -C "$seed_dir" config user.name "Test"
  cat > "$seed_dir/cwt.sh" <<'EOF'
#!/usr/bin/env zsh
CWT_VERSION="0.2.0"
EOF
  git -C "$seed_dir" add cwt.sh
  git -C "$seed_dir" commit -m "initial cwt script" --quiet
  git -C "$seed_dir" push origin HEAD:main --quiet
  git -C "$remote_dir" symbolic-ref HEAD refs/heads/main

  git clone --branch main "$remote_dir" "$install_dir" --quiet

  git clone --branch main "$remote_dir" "$pusher_dir" --quiet
  git -C "$pusher_dir" config user.email "test@test.com"
  git -C "$pusher_dir" config user.name "Test"
  cat > "$pusher_dir/cwt.sh" <<'EOF'
#!/usr/bin/env zsh
# same version, newer commit
CWT_VERSION="0.2.0"
EOF
  git -C "$pusher_dir" commit -am "same version, newer commit" --quiet
  git -C "$pusher_dir" push origin HEAD:main --quiet

  run zsh -c "
    export NO_COLOR=1
    export CWT_DIR='$install_dir'
    source '$CWT_SH'
    cwt update
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated cwt to latest commit (v0.2.0)."* ]]
  [[ "$output" != *"Already up to date"* ]]
}
