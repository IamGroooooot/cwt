# cwt

[![CI](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml/badge.svg)](https://github.com/IamGroooooot/cwt/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://github.com/koalaman/shellcheck)

[English](README.md)

**AI Worktree Manager** — 격리된 git worktree를 생성하고 코딩 어시스턴트(`claude`, `codex`, `gemini`)를 한 번의 명령으로 실행합니다.

```
cwt new fix-auth main
```

worktree를 생성하고, 새 브랜치를 체크아웃하고, 설정 파일을 복사한 뒤 어시스턴트 세션을 시작합니다.

`cwt`는 기존 git 저장소 안에서 실행합니다. 셸 연동은 `zsh`를 기준으로 제공합니다.

## 빠른 시작

설치한 뒤 셸을 다시 읽고, git 저장소로 이동한 다음 `cwt new`를 실행하면 됩니다.
기본적으로 `zsh`와 `git`이 필요하고, 어시스턴트 자동 실행이 필요할 때만 해당 CLI를 설치하면 됩니다.
`~/.config/cwt/config.yaml`이 아직 없으면 첫 대화형 실행에서 짧은 setup wizard가 열립니다. 여기서 기본 `.worktrees` 구조를 그대로 쓰거나, 기존 Claude/Codex worktree 폴더를 재사용하거나, 다른 디렉토리를 직접 고를 수 있습니다.

```sh
# 설치 (권장)
curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh

# 셸 다시 읽기
source ~/.zshrc

# 아무 git 저장소로 이동
cd /path/to/your/repo

# worktree만 생성
cwt new fix-auth --no-launch

# 또는 worktree 생성 후 어시스턴트 실행
cwt new fix-auth --assistant codex
```

## 설치 방법

처음이면 권장 설치부터 시작하는 편이 가장 빠릅니다.
패키지 매니저로 업데이트하고 싶으면 Homebrew, 이미 zsh 플러그인 매니저를 쓰고 있으면 그 방식, 설치 위치를 직접 관리해야 하면 수동 설치를 고르세요.

### 권장 설치

```sh
curl -fsSL https://raw.githubusercontent.com/IamGroooooot/cwt/main/install.sh | sh
```

대부분의 사용자에게 가장 빠른 경로입니다.
`cwt` 설치, `source` 설정, zsh completion 설정까지 한 번에 끝냅니다.

### Homebrew

```sh
brew install IamGroooooot/cwt/cwt
```

Homebrew는 `IamGroooooot/cwt`를 tap 저장소 `IamGroooooot/homebrew-cwt`로 해석합니다.
Homebrew로 설치한 뒤에는 caveats 출력에 따라 `.zshrc`가 Homebrew prefix를 가리키도록 설정하세요.

<details>
<summary>고급 Homebrew</summary>

```sh
# IamGroooooot/cwt의 최신 main 브랜치
brew install --HEAD IamGroooooot/cwt/cwt

# 로컬 체크아웃 또는 커밋 전 변경 테스트
source ./cwt.sh
```

`brew install`은 최신 태그 릴리스를 설치하고, `--HEAD`는 `IamGroooooot/cwt`의 최신 `main` 커밋을 설치합니다.
Homebrew 5부터는 포뮬러가 tap 안에 있어야 하므로, 로컬 체크아웃 테스트는 Homebrew 대신 `./cwt.sh`를 직접 source 하세요.

</details>

### 플러그인 매니저

```zsh
# zinit
zinit light IamGroooooot/cwt

# antigen
antigen bundle IamGroooooot/cwt

# oh-my-zsh
git clone https://github.com/IamGroooooot/cwt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cwt
# .zshrc의 plugins=(...)에 'cwt' 추가
```

### 수동 또는 커스텀 설치

```sh
git clone --depth 1 https://github.com/IamGroooooot/cwt.git ~/.cwt
echo 'fpath=("$HOME/.cwt/completions" $fpath)' >> ~/.zshrc
echo '[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

`~/.cwt`가 아닌 다른 경로에 설치했다면 위 두 줄의 경로도 같은 값으로 바꾸세요.

## 탭 자동완성

설치 시 zsh 탭 자동완성이 자동으로 설정됩니다. 설치 후 다음과 같이 사용할 수 있습니다:

```
cwt <TAB>        → new, ls, cd, rm, config, update (설명 포함)
cwt new <TAB>    → worktree 이름 제안
cwt new --<TAB>  → --help, --assistant, --claude, --codex, --gemini, --launch-target, --current, --split, --tab, --all-permissions, --default-permissions, --yolo, --dangerously-skip-permissions, --no-launch
cwt cd <TAB>     → 기존 worktree 이름 목록
cwt rm <TAB>     → 기존 worktree 이름 목록
cwt rm --<TAB>   → --help, --force/-f
```

**수동 설정** (플러그인 매니저 또는 커스텀 설치):

```zsh
# 예시: ~/.cwt 에 수동 설치한 경우
# .zshrc의 compinit 이전에 추가
fpath=("$HOME/.cwt/completions" $fpath)
[[ -f "$HOME/.cwt/cwt.sh" ]] && source "$HOME/.cwt/cwt.sh"
autoload -Uz compinit && compinit
```

다른 위치에 설치했다면 `$HOME/.cwt`를 실제 설치 경로로 바꾸세요.
Homebrew 설치라면 caveats 출력의 경로를 그대로 사용하는 편이 안전합니다.

## 사용법

```
cwt [전역 옵션] <명령> [옵션]

명령:
  new      새 worktree를 생성하고 어시스턴트 실행
  ls       모든 worktree 상태 목록 표시
  cd       기존 worktree로 이동
  rm       worktree 제거
  config   현재 프로젝트의 worktree 루트 조회 또는 변경
  update   cwt 자체 업데이트

전역 옵션:
  -q, --quiet      정보 메시지 숨기기
  -h, --help       도움말 표시
  -v, --version    버전 표시
```

### 빠른 사용 예시

```sh
cwt new fix-auth --assistant codex               # 생성 + 현재 셸에서 실행
cwt new fix-auth --assistant codex --split       # 생성 + 분할 창에서 실행 (tmux/zellij)
cwt new fix-auth --no-launch                     # 생성만
cwt config ../repo-worktrees                     # 이 저장소의 worktree 루트 저장
```

### worktree 생성

```sh
cwt new fix-auth                # 대화형으로 베이스 브랜치 선택
cwt new fix-auth main           # main 기반
cwt new fix-auth main feat/x    # 명시적 브랜치 이름
cwt new fix-auth --assistant codex   # 생성 후 codex 실행
cwt new fix-auth --gemini            # 생성 후 gemini 실행
cwt new fix-auth --assistant codex --split   # tmux/zellij 분할 창
cwt new fix-auth --assistant codex --tab     # tmux 윈도우 / zellij 탭
cwt new fix-auth --assistant codex --all-permissions   # codex + --yolo
cwt new fix-auth --yolo              # 단축: --assistant codex --all-permissions
cwt new fix-auth --dangerously-skip-permissions  # 단축: --assistant claude --all-permissions
cwt new --no-launch my-task          # 어시스턴트 실행 건너뛰기
```

[fzf](https://github.com/junegunn/fzf)가 설치되어 있으면 브랜치 선택, worktree 선택, setup wizard의 위치/폴더 선택에 우선적으로 사용됩니다. 그렇지 않으면 번호 목록과 화살표 브라우저로 동작합니다.
기본 `.worktrees` 디렉토리를 사용할 때 `cwt new`는 자동으로 `.gitignore`에 `.worktrees/`를 추가합니다.
`CWT_AUTO_LAUNCH=false`일 때도 명시적 실행 플래그(`--assistant`, `--split`, `--tab`, `--launch-target`)는 어시스턴트를 실행합니다.

### worktree 목록

```sh
cwt ls
```

각 worktree의 브랜치 이름, clean/dirty 상태, 마지막 커밋, 상대 시간을 표시합니다.

데이터 테이블은 stdout으로, 장식은 stderr로 출력되므로 파이프 연결이 가능합니다:

```sh
cwt ls 2>/dev/null | grep dirty
```

### worktree 이동

```sh
cwt cd fix-auth            # worktree 디렉토리로 이동
cwt cd fix-auth --assistant codex
cwt cd fix-auth --gemini
cwt cd fix-auth --assistant codex --split
cwt cd fix-auth --assistant codex --tab
cwt cd fix-auth --assistant codex --all-permissions
cwt cd fix-auth --yolo
cwt cd fix-auth --dangerously-skip-permissions
cwt cd                     # 대화형 선택
```

연결된 worktree 내부에서 이름 없이 `cwt cd`를 실행하면 메인 저장소로 이동하고 사용 가능한 다른 worktree를 안내합니다.

### 실행 대상 (tmux/zellij)

어시스턴트 세션을 다른 창/탭에서 실행하려면:

```sh
cwt new fix-auth --assistant codex --launch-target split
cwt new fix-auth --assistant codex --split
cwt cd fix-auth --assistant codex --tab
cwt cd fix-auth --assistant codex --current
```

- `current` (기본값): 현재 셸에서 실행
- `split`: 새 분할 창에서 실행
- `tab`: 새 탭에서 실행 (`tmux` 윈도우 / `zellij` 탭)

폴백 동작:
- 설정/환경 변수에 실행 대상이 설정되어 있고 tmux/zellij 세션이 활성화되지 않은 경우 경고 후 현재 셸에서 실행합니다.
- `--split`/`--tab`/`--launch-target`을 명시적으로 전달했는데 tmux/zellij 세션이 없으면 오류를 반환합니다.

`cwt new`에서의 실행 우선순위:
- `--assistant`, `--current`, `--split`, `--tab`, `--launch-target`은 `CWT_AUTO_LAUNCH=false`일 때도 강제 실행합니다.
- `--no-launch`가 동일 명령에서 나중에 전달되면 실행을 건너뜁니다 (마지막 플래그 우선).

### 전체 권한 실행 모드

기본 동작을 유지하면서 필요할 때만 활성화:

```sh
cwt new fix-auth --assistant codex --all-permissions
cwt cd fix-auth --assistant claude --all-permissions
```

- `--all-permissions`: 전체 권한 모드 활성화
  - Codex: `--yolo` 추가
  - Claude: `--dangerously-skip-permissions` 추가
- `--default-permissions`: 기본 모드 강제
- `--yolo`: `--assistant codex --all-permissions`의 단축
- `--dangerously-skip-permissions`: `--assistant claude --all-permissions`의 단축

### worktree 제거

```sh
cwt rm fix-auth        # 제거 전 확인
cwt rm -f fix-auth     # 확인 건너뛰기
cwt rm                 # 대화형 선택
```

worktree 디렉토리와 연결된 브랜치를 제거합니다.
특정 이름을 전달했는데 worktree가 없으면 `cwt rm <name>`은 오류를 반환합니다.

### cwt 업데이트

```sh
cwt update
```

git 기반 설치(예: `~/.cwt`)의 경우 최신 커밋을 풀한 후 `cwt.sh`를 다시 소싱합니다.

커스텀 경로에 cwt를 설치한 경우 업데이트 전에 `CWT_DIR`을 설정하세요:

```sh
CWT_DIR=/path/to/cwt cwt update
```

Homebrew로 설치한 경우:

```sh
brew upgrade IamGroooooot/cwt/cwt
```

`--HEAD`로 설치했다면 다음 명령으로 최신 `main` 커밋을 가져오세요:

```sh
brew upgrade --fetch-HEAD IamGroooooot/cwt/cwt
```

플러그인 매니저로 설치한 경우 해당 매니저를 통해 업데이트하거나, `CWT_DIR`을 플러그인 체크아웃 경로로 지정한 후 `cwt update`를 실행하세요.

### 조용한 모드

서브커맨드 앞에 `-q` 또는 `--quiet`를 사용하면 정보 메시지(info 및 항목별 출력)를 숨깁니다. 오류와 성공 메시지는 계속 표시됩니다.

```sh
cwt -q new fix-auth main       # 조용하게 worktree 생성
cwt --quiet ls                  # 최소 출력으로 목록 표시
```

### 비대화형 모드

stdin이 TTY가 아닌 경우(예: CI 또는 스크립트) cwt는 프롬프트를 기다리지 않고 즉시 실패합니다:

- `cwt new`: 이름 없이 실행하면 사용법 안내와 함께 오류 반환.
- `cwt cd`: 메인 저장소에서 이름 없이 실행하면 비대화형 모드에서만 오류 반환.
- `cwt rm`: worktree가 있을 때 이름 없이 실행하면 사용법 안내와 함께 오류 반환.
- `cwt rm <name>`: `--force` 없이 실행하면 확인 프롬프트를 표시할 수 없어 오류 반환.
- `cwt new <name>`: 비대화형 모드에서 베이스 브랜치 없이 실행하면 `HEAD`를 기본값으로 사용.

### 엄격한 옵션 파싱

서브커맨드는 알 수 없는 플래그를 오류와 도움말 안내로 거부합니다:

- `cwt new`, `cwt cd`, `cwt rm`, `cwt ls`, `cwt update`는 지원되지 않는 옵션에 대해 실패합니다.
- 각 서브커맨드의 유효한 옵션은 `cwt <command> --help`로 확인하세요.

## `.worktreeinclude`

프로젝트 루트에 `.worktreeinclude` 파일을 배치하면 새 worktree에 파일을 자동 복사합니다:

```
# .worktreeinclude
.env
.env.local
config/*.secret.json
```

항목은 반드시 저장소 내부 경로여야 합니다. 부모 경로 탈출이나 저장소 밖을 가리키는 symlink는 `cwt`가 건너뜁니다.

## 설정

cwt는 실행할 때마다 선택적 설정 파일을 읽습니다:

```
~/.config/cwt/config.yaml
```

경로를 변경하려면 `CWT_CONFIG=/path/to/config`를 설정하세요.
현재 git 프로젝트에 cwt 설정이 없으면 첫 대화형 실행에서 그 프로젝트용 설정 마법사가 자동으로 열립니다.
마법사는 기본 `.worktrees` 구조, 감지된 Claude/Codex worktree 폴더 재사용, 또는 git root의 부모부터 시작하는 커스텀 폴더 선택을 제공합니다.

현재 저장소의 worktree 루트를 확인하거나 바꾸고 싶다면 `cwt config`를 사용하면 됩니다:

```sh
cwt config                  # 현재 프로젝트 설정 보기
cwt config --browse         # 대화형으로 폴더 선택
cwt config ../repo-worktrees
cwt config --default        # 다시 .worktrees 사용
```

### 설정 옵션

```yaml
# ~/.config/cwt/config.yaml

version: 1

defaults:
  default_base_branch: 'main'
  default_assistant: 'claude'
  auto_launch: 'false'
  launch_target: 'current'
  permission_mode: 'default'
  cmd_claude: 'claude'
  cmd_codex: 'codex'
  cmd_gemini: 'gemini'

projects:
  - git_root: '/Users/you/src/project-a'
    worktree_dir: '../project-a-worktrees'
  - git_root: '/Users/you/src/project-b'
    worktree_dir: '.worktrees'
```

모든 옵션은 선택 사항입니다. 설정하지 않은 값은 기본 동작을 유지합니다.
`defaults` 블록은 전역 기본값이고, `projects[*].worktree_dir`는 git root별로 따로 저장됩니다. 그래서 저장소마다 다른 worktree 위치를 안전하게 둘 수 있습니다.
`worktree_dir`는 절대 경로도 사용할 수 있고, 상대 경로를 쓰면 `cwt`를 실행한 현재 위치가 아니라 메인 git root 기준으로 해석합니다.
안전을 위해 `/`, git root 자체, `.git` 내부처럼 명백히 위험한 위치는 거부합니다.
커스텀 worktree 루트를 쓰는 경우 `cwt new`는 생성 전에 해석된 실제 경로를 먼저 보여줍니다.
예전 `~/.config/cwt/config` 파일이 남아 있으면 하위 호환으로 읽고, 다음 저장 시점부터는 다시 YAML 형식으로 저장합니다.

## 동작 원리

기본적으로 worktree는 `<project>/.worktrees/<name>` 아래에 생성됩니다.
현재 프로젝트에 `worktree_dir`가 설정되어 있으면 그 디렉토리를 사용하고, 생성 전에 해석된 실제 루트를 먼저 보여줍니다.
각 worktree는 새 브랜치(`wt/<name>-<rand>` 형식)를 가지며, `.worktreeinclude`에 나열된 파일을 선택적으로 복사합니다. 설정이 완료되면 선택된 어시스턴트 명령이 worktree 디렉토리에서 실행됩니다.

## 요구사항

- **zsh** (macOS 기본 셸)
- **git** 2.15+
- **fzf** *(선택, 대화형 선택용)*
- **지원되는 어시스턴트 CLI** *(선택, `--no-launch`가 아니면 자동 실행)*
  - `claude`
  - `codex`
  - `gemini` 또는 `gemini-cli`
- **tmux 또는 zellij** *(선택, `--split`/`--tab` 전용)*

## 제거

git 기반 설치 (기본):

```sh
~/.cwt/uninstall.sh
```

Homebrew 설치:

```sh
brew uninstall IamGroooooot/cwt/cwt
```

플러그인 매니저 설치의 경우 플러그인 체크아웃을 제거하고 셸 설정에서 관련 `cwt` 라인을 삭제하세요.

## 라이선스

[MIT](LICENSE)
