# cwt - Claude Worktree Manager

Git worktree를 인터랙티브하게 생성/관리하는 zsh 함수 모음.
워크트리 생성 후 자동으로 `claude`를 실행한다.

## 설치

```zsh
# .zshrc에 추가
fpath=(~/.zfunc $fpath)
autoload -Uz cwt cwt-rm cwt-ls _cwt_init
```

## 명령어

| 명령어 | 설명 |
|--------|------|
| `cwt [name] [base] [branch]` | 워크트리 생성 |
| `cwt-rm` | 워크트리 선택 후 제거 |
| `cwt-ls` | 워크트리 목록 + 브랜치/최근 커밋 표시 |

## 사용 예시

```zsh
# 인터랙티브 (fzf로 브랜치 선택)
cwt my-feature

# 전부 지정
cwt my-feature main feat/my-feature

# 목록 확인
cwt-ls

# 제거
cwt-rm
```

## .worktreeinclude

프로젝트 루트에 `.worktreeinclude` 파일을 두면, 워크트리 생성 시 지정한 파일을 자동 복사한다.

```
# .worktreeinclude 예시
.env
.env.local
config/*.secret.json
```

## 의존성

- **필수**: git, zsh
- **권장**: [fzf](https://github.com/junegunn/fzf) (인터랙티브 선택)
- **선택**: [claude](https://claude.ai/claude-code) (워크트리 생성 후 자동 실행)
