# cwt

[![CI](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml/badge.svg)](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://github.com/koalaman/shellcheck)

[한국어](README.ko.md)

**AI Worktree Manager** — Create isolated git worktrees and launch your coding assistant (`claude`, `codex`, `gemini`) in one command.

```
cwt new fix-auth main
```

Creates a worktree, checks out a new branch, copies config files, and drops you into an assistant session — all in seconds.

Run `cwt` inside an existing git repository. Shell integration targets `zsh`.

## Quick Start

Install it, reload your shell, move into any git repository, and run `cwt new`.
You need `zsh` and `git`; assistant CLIs are optional unless you want auto-launch.
If `~/.config/cwt/config` does not exist yet, the first interactive run walks you through where to keep this project's worktrees. You can stick with the default `.worktrees` layout, reuse detected Claude or Codex worktree folders, or pick and create another folder.

```sh
# install (recommended)
curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh

# reload your shell
source ~/.zshrc

# move into any git repository
cd /path/to/your/repo

# create a worktree only
cwt new fix-auth --no-launch

# or create a worktree and launch an assistant
cwt new fix-auth --assistant codex
```

## Install Methods

If you're not sure, use the installer.
Choose Homebrew for package-managed updates, a plugin manager if you already manage zsh plugins that way, and manual install only when you want a custom checkout path.

### Recommended installer

```sh
curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
```

This is the shortest path for most users.
It installs `cwt`, adds the `source` line, and enables zsh completion automatically.

### Homebrew

```sh
brew install IamGroooooot/cwt/cwt
```

Homebrew resolves `IamGroooooot/cwt` to the tap repository `IamGroooooot/homebrew-cwt`.
After installing via Homebrew, follow the caveats output so your `.zshrc` points at the Homebrew prefix.

<details>
<summary>Advanced Homebrew</summary>

```sh
# latest main branch from IamGroooooot/cwt
brew install --HEAD IamGroooooot/cwt/cwt

# local checkout or uncommitted changes
source ./cwt.sh
```

Use `brew install` for the latest tagged release and `--HEAD` for the latest `main` commit from `IamGroooooot/cwt`.
Homebrew 5 requires formulae to live in a tap, so local checkout testing should source `./cwt.sh` directly instead of going through Homebrew.

</details>

### Plugin managers

```zsh
# zinit
zinit light IamGroooooot/cwt

# antigen
antigen bundle IamGroooooot/cwt

# oh-my-zsh
git clone https://github.com/IamGroooooot/cwt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cwt
# then add 'cwt' to plugins=(...) in .zshrc
```

### Manual or custom install

```sh
git clone --depth 1 https://github.com/IamGroooooot/cwt.git ~/.cwt
echo 'fpath=("$HOME/.cwt/completions" $fpath)' >> ~/.zshrc
echo '[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

If you install somewhere other than `~/.cwt`, replace that path in both lines above.

## Tab Completion

The installer automatically sets up zsh tab completion. After installing, you get:

```
cwt <TAB>        → new, ls, cd, rm, update (with descriptions)
cwt new <TAB>    → suggest worktree name
cwt new --<TAB>  → --help, --assistant, --claude, --codex, --gemini, --launch-target, --current, --split, --tab, --all-permissions, --default-permissions, --yolo, --dangerously-skip-permissions, --no-launch
cwt cd <TAB>     → list existing worktree names
cwt rm <TAB>     → list existing worktree names
cwt rm --<TAB>   → --help, --force/-f
```

**Manual setup** (for plugin managers or custom installs):

```zsh
# Example: manual install at ~/.cwt
# Add to .zshrc BEFORE compinit
fpath=("$HOME/.cwt/completions" $fpath)
[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"
autoload -Uz compinit && compinit
```

If you installed somewhere else, replace `$HOME/.cwt` with your actual install path.
If you installed via Homebrew, use the caveats output so the path matches your Homebrew prefix.

## Usage

```
cwt [global-options] <command> [options]

Commands:
  new      Create a new worktree and launch an assistant
  ls       List all worktrees with status
  cd       Enter an existing worktree
  rm       Remove a worktree
  update   Self-update cwt

Global Options:
  -q, --quiet      Suppress informational messages
  -h, --help       Show help
  -v, --version    Show version
```

### Quick flows

```sh
cwt new fix-auth --assistant codex               # create + launch in current shell
cwt new fix-auth --assistant codex --split       # create + launch in split pane (tmux/zellij)
cwt new fix-auth --no-launch                     # create only
```

### Create a worktree

```sh
cwt new fix-auth                # pick base branch interactively
cwt new fix-auth main           # base off main
cwt new fix-auth main feat/x    # explicit branch name
cwt new fix-auth --assistant codex   # launch codex after create
cwt new fix-auth --gemini            # launch gemini after create
cwt new fix-auth --assistant codex --split   # tmux pane / zellij pane
cwt new fix-auth --assistant codex --tab     # tmux window / zellij tab
cwt new fix-auth --assistant codex --all-permissions   # codex + --yolo
cwt new fix-auth --yolo              # shortcut: --assistant codex --all-permissions
cwt new fix-auth --dangerously-skip-permissions  # shortcut: --assistant claude --all-permissions
cwt new --no-launch my-task          # skip assistant launch
```

If [fzf](https://github.com/junegunn/fzf) is installed, branch selection becomes interactive. Otherwise, a numbered list is shown.
When the default `.worktrees` directory is used, `cwt new` automatically ensures `.worktrees/` is present in `.gitignore`.
When `CWT_AUTO_LAUNCH=false`, explicit launch flags (for example `--assistant`, `--split`, `--tab`, `--launch-target`) still launch.

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
cwt cd fix-auth --assistant codex
cwt cd fix-auth --gemini
cwt cd fix-auth --assistant codex --split
cwt cd fix-auth --assistant codex --tab
cwt cd fix-auth --assistant codex --all-permissions
cwt cd fix-auth --yolo
cwt cd fix-auth --dangerously-skip-permissions
cwt cd                     # interactive selection
```

When you run `cwt cd` with no name from inside a linked worktree, it moves you back to the main repository and suggests other available worktrees.

### Launch target (tmux/zellij)

Use launch target options when you want assistant sessions in another pane/tab:

```sh
cwt new fix-auth --assistant codex --launch-target split
cwt new fix-auth --assistant codex --split
cwt cd fix-auth --assistant codex --tab
cwt cd fix-auth --assistant codex --current
```

- `current` (default): launch in current shell
- `split`: launch in a new split pane
- `tab`: launch in a new tab (`tmux` window / `zellij` tab)

Fallback behavior:
- If launch target is set in config/env and no tmux/zellij session is active, cwt warns and launches in current shell.
- If `--split`/`--tab`/`--launch-target` is explicitly passed and no tmux/zellij session is active, cwt returns an error.

Launch precedence in `cwt new`:
- `--assistant`, `--current`, `--split`, `--tab`, and `--launch-target` force launch even when `CWT_AUTO_LAUNCH=false`.
- If `--no-launch` is passed later in the same command, launch is skipped (last flag wins).

### Full-permission launch mode

Keep default behavior as-is, and opt in only when needed:

```sh
cwt new fix-auth --assistant codex --all-permissions
cwt cd fix-auth --assistant claude --all-permissions
```

- `--all-permissions`: enable full-permission mode
  - Codex: adds `--yolo`
  - Claude: adds `--dangerously-skip-permissions`
- `--default-permissions`: force normal/default mode
- `--yolo`: shortcut for `--assistant codex --all-permissions`
- `--dangerously-skip-permissions`: shortcut for `--assistant claude --all-permissions`

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

For git-based installs (for example `~/.cwt`), `cwt update` pulls the latest commit and re-sources `cwt.sh`.

If you installed cwt in a custom path, set `CWT_DIR` before running update:

```sh
CWT_DIR=/path/to/cwt cwt update
```

If you installed via Homebrew, update with:

```sh
brew upgrade IamGroooooot/cwt/cwt
```

If you installed with `--HEAD`, fetch the latest `main` commit with:

```sh
brew upgrade --fetch-HEAD IamGroooooot/cwt/cwt
```

If you installed via a plugin manager, update through the plugin manager, or point `CWT_DIR` to that plugin checkout and run `cwt update`.

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
If the file does not exist yet, the first interactive run can create it for you.
The setup wizard offers the default `.worktrees` layout, detected Claude or Codex worktree folders when they exist, or a custom directory picker that starts from the parent of your git root.

### Available options

```sh
# ~/.config/cwt/config

# Skip the interactive base-branch prompt and always use this branch
CWT_DEFAULT_BASE_BRANCH=main

# Default assistant used by cwt new/cd when launch is requested
CWT_DEFAULT_ASSISTANT=claude

# Set to "false" to skip launching after cwt new by default (same as --no-launch)
CWT_AUTO_LAUNCH=false

# Default launch target for assistant startup
# one of: current, split, tab
CWT_LAUNCH_TARGET=current

# Default assistant permission mode when launching
# one of: default, full
CWT_PERMISSION_MODE=default

# Custom worktree directory (default: <git-root>/.worktrees)
# Relative paths are resolved from the main git root.
CWT_WORKTREE_DIR=../projectA-worktrees

# Optional command overrides
CWT_CMD_CLAUDE=claude
CWT_CMD_CODEX=codex
CWT_CMD_GEMINI=gemini
```

All options are optional. Unset values keep the default behavior.
`CWT_WORKTREE_DIR` accepts absolute paths too, but relative paths are resolved from the main git root, not from the directory where you run `cwt`.
For safety, cwt rejects obviously unsafe destinations such as `/`, the git root itself, or anything inside `.git`.
When a custom worktree root is active, `cwt new` prints the resolved destination before creating anything.

## How it works

By default, worktrees are created under `<project>/.worktrees/<name>`.
If `CWT_WORKTREE_DIR` is set, cwt uses that directory instead and shows the resolved root before creation.
Each worktree gets a new branch (`wt/<name>-<rand>` by default) and can copy files listed in `.worktreeinclude`. After setup, the selected assistant command is launched in the worktree directory.

## Requirements

- **zsh** (macOS default)
- **git** 2.15+
- **fzf** *(optional, for interactive selection)*
- **Any supported assistant CLI** *(optional, auto-launched unless `--no-launch`)*
  - `claude`
  - `codex`
  - `gemini` or `gemini-cli`
- **tmux or zellij** *(optional, only for `--split`/`--tab`)*

## Uninstall

For git-based installs (default):

```sh
~/.cwt/uninstall.sh
```

For Homebrew installs:

```sh
brew uninstall IamGroooooot/cwt/cwt
```

For plugin-manager installs, remove the plugin checkout and related `cwt` lines from your shell config.

## License

[MIT](LICENSE)
