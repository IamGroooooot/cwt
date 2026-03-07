#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/render-homebrew-formula.sh --tag vX.Y.Z [--sha SHA256] [--output PATH]

Renders the Homebrew formula for a tagged cwt release. When --sha is omitted,
the script downloads the source tarball from GitHub and computes the checksum.
EOF
}

compute_sha256() {
	local file_path="$1"

	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file_path" | awk '{print $1}'
		return
	fi

	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file_path" | awk '{print $1}'
		return
	fi

	echo "error: missing shasum or sha256sum" >&2
	exit 1
}

SOURCE_REPO="${SOURCE_REPO:-IamGroooooot/cwt}"
FORMULA_NAME="${FORMULA_NAME:-cwt}"

tag=""
sha256=""
output_path=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--tag)
		tag="${2:-}"
		shift 2
		;;
	--sha)
		sha256="${2:-}"
		shift 2
		;;
	--output)
		output_path="${2:-}"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "error: unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [[ -z "$tag" ]]; then
	echo "error: --tag is required" >&2
	usage >&2
	exit 1
fi

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: tag must look like v0.2.14" >&2
	exit 1
fi

if [[ -z "$sha256" ]]; then
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT

	tarball_path="$tmpdir/${FORMULA_NAME}-${tag}.tar.gz"
	curl -fsSL \
		-o "$tarball_path" \
		"https://github.com/${SOURCE_REPO}/archive/refs/tags/${tag}.tar.gz"
	sha256="$(compute_sha256 "$tarball_path")"
fi

formula_content="$(
	cat <<EOF
class Cwt < Formula
  desc "AI Worktree Manager - git worktrees for parallel coding sessions"
  homepage "https://github.com/${SOURCE_REPO}"
  url "https://github.com/${SOURCE_REPO}/archive/refs/tags/${tag}.tar.gz"
  sha256 "${sha256}"
  license "MIT"
  head "https://github.com/${SOURCE_REPO}.git", branch: "main"

  depends_on "git"
  depends_on "zsh"

  def install
    prefix.install "cwt.sh"
    prefix.install "cwt.plugin.zsh"
    prefix.install "completions"
  end

  def caveats
    <<~EOS
      Add the following to your ~/.zshrc:

        fpath=("#{opt_prefix}/completions" \$fpath)
        [[ -f "#{opt_prefix}/cwt.sh" ]] && source "#{opt_prefix}/cwt.sh"
        autoload -Uz compinit && compinit

      Then restart your shell or run: source ~/.zshrc
    EOS
  end

  test do
    assert_match(/^cwt \S+$/, shell_output("zsh -c 'source #{opt_prefix}/cwt.sh && cwt --version'").strip)
  end
end
EOF
)"

if [[ -n "$output_path" ]]; then
	mkdir -p "$(dirname "$output_path")"
	printf '%s\n' "$formula_content" >"$output_path"
else
	printf '%s\n' "$formula_content"
fi
