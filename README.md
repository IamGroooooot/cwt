# cwt

[![CI](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml/badge.svg)](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://github.com/koalaman/shellcheck)

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
<summary>Homebrew (tap)</summary>

```sh
brew tap IamGroooooot/cwt
brew install cwt
```

After installing via Homebrew, follow the caveats output to add the source line to your `.zshrc`.

</details>

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

## Tab Completion

The installer automatically sets up zsh tab completion. After installing, you get:

```
cwt <TAB>        → new, ls, cd, rm, update (with descriptions)
cwt new <TAB>    → suggest worktree name
cwt new --<TAB>  → --help, --no-claude
cwt cd <TAB>     → list existing worktree names
cwt rm <TAB>     → list existing worktree names
cwt rm --<TAB>   → --help, --force/-f
```

**Manual setup** (for plugin managers or custom installs):

```zsh
# Add to .zshrc BEFORE compinit
fpath=("$HOME/.cwt/completions" $fpath)
autoload -Uz compinit && compinit
```

## Usage

```
cwt [global-options] <command> [options]

Commands:
  new      Create a new worktree and launch Claude Code
  ls       List all worktrees with status
  cd       Enter an existing worktree
  rm       Remove a worktree
  update   Self-update cwt

Global Options:
  -q, --quiet      Suppress informational messages
  -h, --help       Show help
  -v, --version    Show version
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

The data table is printed to stdout while decorations go to stderr, so output is pipeable:

```sh
cwt ls 2>/dev/null | grep dirty
```

### Enter a worktree

```sh
cwt cd fix-auth            # enter worktree directory
cwt cd fix-auth --claude   # enter and launch Claude Code
cwt cd                     # interactive selection
```

When you run `cwt cd` with no name from inside a linked worktree, it moves you back to the main repository and suggests other available worktrees.

### Remove a worktree

```sh
cwt rm fix-auth        # confirm before removing
cwt rm -f fix-auth     # skip confirmation
cwt rm                 # interactive selection
```

Removes the worktree directory and its associated branch.
If you pass a specific name and no worktrees exist, `cwt rm <name>` returns an error.

### Update cwt

```sh
cwt update
```

Pulls the latest version from git and re-sources `cwt.sh`. Requires cwt to be installed via `git clone` (not Homebrew).

### Quiet mode

Use `-q` or `--quiet` before the subcommand to suppress informational messages (info and item-level output). Errors and success messages are still shown.

```sh
cwt -q new fix-auth main       # create worktree quietly
cwt --quiet ls                  # list with minimal output
```

### Non-interactive mode

When stdin is not a TTY (for example in CI or scripts), cwt fails fast instead of waiting on prompts:

- `cwt new` without a name returns an error with usage guidance.
- `cwt cd` without a name returns an error in non-interactive mode only when run from the main repository.
- `cwt rm` without a name returns an error with usage guidance when worktrees exist.
- `cwt rm <name>` without `--force` returns an error because confirmation cannot be prompted.
- `cwt new <name>` without a base branch defaults to `HEAD` in non-interactive mode.

### Strict option parsing

Subcommands now reject unknown flags with an error and a help hint:

- `cwt new`, `cwt cd`, `cwt rm`, `cwt ls`, and `cwt update` fail on unsupported options.
- Use `cwt <command> --help` to see valid options for each subcommand.

## `.worktreeinclude`

Place a `.worktreeinclude` file in your project root to auto-copy files into new worktrees:

```
# .worktreeinclude
.env
.env.local
config/*.secret.json
```

## Configuration

cwt reads an optional config file on each invocation:

```
~/.config/cwt/config
```

Override the path with `CWT_CONFIG=/path/to/config`.

### Available options

```sh
# ~/.config/cwt/config

# Skip the interactive base-branch prompt and always use this branch
CWT_DEFAULT_BASE_BRANCH=main

# Set to "false" to skip launching Claude Code by default (same as --no-claude)
CWT_AUTO_CLAUDE=false

# Custom worktree directory (default: <git-root>/.claude/worktrees)
CWT_WORKTREE_DIR=
```

All options are optional. Unset values keep the default behavior.

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
