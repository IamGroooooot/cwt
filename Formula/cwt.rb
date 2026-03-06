class Cwt < Formula
  desc "AI Worktree Manager - git worktrees for parallel coding sessions"
  homepage "https://github.com/IamGroooooot/cwt"
  url "https://github.com/IamGroooooot/cwt/archive/refs/tags/v0.2.9.tar.gz"
  sha256 "7e14918276cec4fbd6cc291d9bb5e256d8af2292baa3dd9f7507c092d98b90f4"
  license "MIT"

  depends_on "git"
  depends_on "zsh"

  def install
    prefix.install "cwt.sh"
    prefix.install "cwt.plugin.zsh"
    prefix.install Dir["completions"]
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
    assert_match "cwt #{version}", shell_output("zsh -c 'source #{opt_prefix}/cwt.sh && cwt --version'")
  end
end
