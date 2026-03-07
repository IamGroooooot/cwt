class Cwt < Formula
  desc "AI Worktree Manager - git worktrees for parallel coding sessions"
  homepage "https://github.com/IamGroooooot/cwt"
  url "https://github.com/IamGroooooot/cwt/archive/refs/tags/v0.2.16.tar.gz"
  sha256 "6dfd7d5e3f5d73ce82999b9adaeb77e09e45dad5adf927722714a72f774c51de"
  license "MIT"
  head "https://github.com/IamGroooooot/cwt.git", branch: "main"

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

        fpath=("#{opt_prefix}/completions" $fpath)
        [[ -f "#{opt_prefix}/cwt.sh" ]] && source "#{opt_prefix}/cwt.sh"
        autoload -Uz compinit && compinit

      Then restart your shell or run: source ~/.zshrc
    EOS
  end

  test do
    assert_match(/^cwt \S+$/, shell_output("zsh -c 'source #{opt_prefix}/cwt.sh && cwt --version'").strip)
  end
end
