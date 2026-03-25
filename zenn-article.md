---
title: "Claude Code に「記憶」を持たせる — 外部サービス不要・コストゼロの自作メモリ層"
emoji: "🧠"
type: "tech"
topics: ["claudecode", "claude", "ai", "shell", "git"]
published: false
---

## はじめに

Claude Code は優秀だが、**セッションをまたいで記憶が完全にリセットされる**。

毎回こんなことを伝え直していないだろうか。

- 「MUIのsxプロパティはpx禁止、spacing単位で書いて」
- 「このプロジェクトはpnpmを使っている」
- 「前回途中になったあの実装、続きから」

これをゼロから解決するツールが **Letta の [claude-subconscious](https://github.com/letta-ai/claude-subconscious)** だ。セッションのトランスクリプト全体を外部サービスに送り、AIが記憶を学習・整理してくれる。

しかし産業系・行政系のプロジェクトでは外部サービスへのコード送信は現実的でない。そして終日・複数リポジトリで Claude Code を動かす使い方では、Letta Cloud のクレジットがすぐ枯渇する。

そこで**外部サービス不要・コストゼロ**で同等の記憶機能を自作した。

## 作ったもの

**[claude-memory-sync](https://github.com/BoxPistols/claude-memory-sync)**

- Claude Code の hook 機構を使い、セッション開始時に記憶を自動注入
- 記憶は Git 管理のプライベートリポジトリに保存
- 複数PCをまたいで同じ記憶が使える
- 外部 API・クレジット消費ゼロ

```bash
# インストール one-liner
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

## claude-subconscious との比較

| | claude-subconscious | claude-memory-sync |
|---|---|---|
| 外部サービス | Letta Cloud（必須） | **不要** |
| コスト | $20/月〜 | **ゼロ** |
| コード送信 | あり | **なし** |
| 記憶の更新 | AI が自動学習 | Claude が追記（半自動） |
| セットアップ | 中程度 | **one-liner** |
| 複数PC対応 | ○ | **○（Git経由）** |

## 仕組み

### Claude Code の hook 機構

Claude Code には4つのフックポイントがある。

```
UserPromptSubmit  → ユーザーがプロンプトを送信したとき
PreToolUse        → ツール実行前
PostToolUse       → ツール実行後
Stop              → Claude が応答を止めたとき
```

これを `~/.claude/settings.json` に設定することで、任意のシェルスクリプトを実行できる。

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/skills/memory-sync/hooks/start.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/skills/memory-sync/hooks/stop.sh" }
        ]
      }
    ]
  }
}
```

### 記憶の構造

```
~/.claude-memory/               ← プライベートGitリポジトリ
  global.md                     # 全PJ共通の設計方針
  repos/
    drone-platform.md           # PJごとの記憶
    nanyo-city.md
```

**global.md** には個人の癖・設計方針を書く。コードは書かない。

```markdown
## コンポーネント設計
- 単一責任。1コンポーネント1責務
- Props は必ず型定義。any 禁止

## MUI
- sx の padding/margin は数値のみ（'8px' はNG、1 と書く）

## Claude への指示スタイル
- 差分だけ返す。ファイル全体を返さない
- 変更理由を1行コメントで添える
```

### セッション開始時の注入

`UserPromptSubmit` hook でこのスクリプトが動く。

```bash
#!/bin/bash
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO=$(basename "$(pwd)")

# 最新を取得
git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true

# CLAUDE.md に記憶を注入
{
  echo "<!-- claude-memory-sync: auto-generated -->"
  [ -f "$MEMORY_DIR/global.md" ]           && cat "$MEMORY_DIR/global.md"
  [ -f "$MEMORY_DIR/repos/${REPO}.md" ]    && cat "$MEMORY_DIR/repos/${REPO}.md"
} >> CLAUDE.md
```

Claude Code はセッション開始時に `CLAUDE.md` を自動で読む。これを動的に生成することで、毎回最新の記憶が Claude に渡る。

### セッション終了時の自動push

`Stop` hook で変更があれば自動コミット・push。

```bash
#!/bin/bash
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"

cd "$MEMORY_DIR"
if [ -n "$(git status --porcelain)" ]; then
  git add .
  git commit -m "auto: $(date '+%m/%d %H:%M')" --quiet
  git push --quiet 2>/dev/null || true
fi
```

## インストール詳細

### 前提

- Claude Code がインストール済み
- Git・Node.js（v18以上）が使える
- GitHubのプライベートリポジトリを1つ作っておく

### one-liner インストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

インストーラが以下を自動でやる。

1. `~/.claude/skills/memory-sync/` に Skill をクローン
2. 記憶リポジトリのGit URLを聞いてクローン（またはローカル初期化）
3. `global.md` のテンプレートを配置
4. `~/.claude/settings.json` に hook を登録
5. `memory` コマンドを `~/.local/bin/` にシンボリックリンク

### 別PCへの展開

2台目以降も同じコマンド一発。

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
# → 既存の記憶リポジトリURLを入力するだけ
```

## 日常の使い方

### 作業開始

```bash
claude    # いつも通り起動するだけ
```

記憶が自動注入されているので、前提の説明は不要。

### 記憶の更新

作業中または終わりに Claude へ一言。

```
今日の知見を記憶して
```

Claude が `~/.claude-memory/repos/{リポジトリ名}.md` に追記する。
`Stop` hook で自動push されるので `memory` は基本不要。

### 手動同期（複数PC切り替え時）

```bash
memory    # pull → commit → push
```

## 複数リポジトリの運用

20リポジトリ並行でも設定は変わらない。

- **個人の癖・設計方針** → `global.md` に書く。全リポジトリで共通
- **PJ固有の文脈** → Claude が自動で `repos/{repo}.md` に分けて記憶

```
drone-platform/ で作業
  → global.md + repos/drone-platform.md が注入される

nanyo-city/ で作業
  → global.md + repos/nanyo-city.md が注入される
```

ディレクトリを移動するだけで自動で切り替わる。

## セキュリティ

記憶ファイルには**方針・パターン・禁止事項のみ**を書く。コードは書かない。

- ソースコードは一切 Git に入らない
- 外部に送信されるものは何もない
- プライベートリポジトリで完全に自己管理

`.letta/` のようなディレクトリがプロジェクトに生成されないので、うっかりコミットのリスクもない。

## Claudeが自分で学習する仕組みにするには

今回の実装では記憶の更新は「Claude に言う」半手動方式。  
全自動にしたい場合は `Stop` hook でサブプロセスとして Claude API を呼ぶことで実現できる。

```bash
# stop.sh の拡張例（コスト注意）
claude --print "
今回のセッションのトランスクリプトから新しい知見を抽出し、
$MEMORY_DIR/repos/${REPO}.md に箇条書きで追記してください。
重複・コードは書かない。
" 2>/dev/null || true
```

ただしこれは Stop hook の中でさらに Claude を呼ぶ再帰的な構造になるので、
最初は半手動で運用して必要になってから追加するのを勧める。

## まとめ

| 機能 | 実現方法 |
|---|---|
| 記憶の注入 | `UserPromptSubmit` hook → CLAUDE.md 動的生成 |
| 記憶の永続化 | プライベート Git リポジトリ |
| 複数PC同期 | Git push/pull |
| 複数PJ分離 | `repos/{repo}.md` で自動分岐 |
| インストール | `install.sh` one-liner |

Claude Code を毎日ヘビーユースしている人、複数リポジトリを並行している人、複数PCを切り替えている人に特に効くと思う。

リポジトリはこちら → https://github.com/BoxPistols/claude-memory-sync
