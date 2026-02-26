# cwt

**Claude Worktree Manager** — Create isolated git worktrees and launch [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in one command.

```
cwt new fix-auth main
```

Creates a worktree, checks out a new branch, copies config files, and drops you into a Claude Code session — all in seconds.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
```

Or manually:

```sh
git clone --depth 1 https://github.com/IamGroooooot/cwt.git ~/.cwt
echo '[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"' >> ~/.zshrc
source ~/.zshrc
```

<details>
<summary>Plugin managers (zinit, antigen, oh-my-zsh)</summary>

```zsh
# zinit
zinit light IamGroooooot/cwt

# antigen
antigen bundle IamGroooooot/cwt

# oh-my-zsh
git clone https://github.com/IamGroooooot/cwt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cwt
# then add 'cwt' to plugins=(...) in .zshrc
```

</details>

## Usage

```
cwt <command> [options]

Commands:
  new    Create a new worktree and launch Claude Code
  ls     List all worktrees with status
  cd     Enter an existing worktree
  rm     Remove a worktree
```

### Create a worktree

```sh
cwt new fix-auth                # pick base branch interactively
cwt new fix-auth main           # base off main
cwt new fix-auth main feat/x    # explicit branch name
cwt new --no-claude my-task     # skip Claude Code launch
```

If [fzf](https://github.com/junegunn/fzf) is installed, branch selection becomes interactive. Otherwise, a numbered list is shown.

### List worktrees

```sh
cwt ls
```

Shows each worktree with branch name, clean/dirty status, last commit, and relative time.

### Enter a worktree

```sh
cwt cd fix-auth            # enter worktree directory
cwt cd fix-auth --claude   # enter and launch Claude Code
cwt cd                     # interactive selection
```

### Remove a worktree

```sh
cwt rm fix-auth        # confirm before removing
cwt rm -f fix-auth     # skip confirmation
cwt rm                 # interactive selection
```

Removes the worktree directory and its associated branch.

## `.worktreeinclude`

Place a `.worktreeinclude` file in your project root to auto-copy files into new worktrees:

```
# .worktreeinclude
.env
.env.local
config/*.secret.json
```

## How it works

Worktrees are created under `<project>/.claude/worktrees/<name>`. Each gets a new branch (`wt/<name>-<rand>` by default) and optionally copies files listed in `.worktreeinclude`. After setup, `claude` is launched in the worktree directory.

## Requirements

- **zsh** (macOS default)
- **git** 2.15+
- **fzf** *(optional, for interactive selection)*
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** *(optional, auto-launched unless `--no-claude`)*

## Uninstall

```sh
~/.cwt/uninstall.sh
```

Or manually: remove `~/.cwt/` and the source line from `.zshrc`.

## License

[MIT](LICENSE)
