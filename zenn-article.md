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

これを解決するOSSが [claude-subconscious](https://github.com/letta-ai/claude-subconscious)（Letta製）だ。セッションのトランスクリプト全体を外部サービスに送り、AIが記憶を学習・整理してくれる本格的なソリューション。

ただし以下の課題がある。

- ソースコードが外部サービス（Letta Cloud）に送信される
- 終日ヘビーユースだとクレジットがすぐ枯渇する（$20/月〜）
- 産業系・行政案件では外部送信がそもそも難しい

そこで**外部サービス不要・コストゼロ**で同等の記憶機能を自作した。

## 作ったもの

**[claude-memory-sync](https://github.com/yourname/claude-memory-sync)**

```bash
curl -fsSL https://raw.githubusercontent.com/yourname/claude-memory-sync/main/install.sh | bash
```

### claude-subconscious との比較

| | claude-subconscious | claude-memory-sync |
|---|---|---|
| 外部サービス | Letta Cloud（必須） | **不要** |
| コスト | $20/月〜 | **ゼロ** |
| コード送信 | あり | **なし** |
| 記憶の更新 | AI が自動学習 | Claude が追記（半自動） |
| 複数PC対応 | ○ | **○（Git経由）** |
| プロジェクト汚染 | なし | **なし** |

## 設計の核心：プロジェクトを汚さない

初期実装で陥りがちなのが、**プロジェクト内の `CLAUDE.md` に記憶を書き込む**パターン。これには問題がある。

- Gitに入れている場合、自動生成された内容がコミットされる
- チームリポジトリだと他のメンバーに影響する
- 手書きの `CLAUDE.md` と内容が混在して管理が煩雑になる

Claude Code はプロジェクト内の `CLAUDE.md` だけでなく、**グローバルの `~/.claude/CLAUDE.md` も自動で読む**。

この仕様を使い、注入先を `~/.claude/CLAUDE.md` に限定した。

```
~/.claude/CLAUDE.md（グローバル）
  ├── （手書きの内容があればそのまま残る）
  └── <!-- claude-memory-sync: auto-generated -->
        ├── global.md の内容
        └── repos/{repo}.md の内容
```

プロジェクト内の `CLAUDE.md` には一切手を加えない。

## 仕組み

### Claude Code の hook 機構

Claude Code には以下のフックポイントがある。

```
UserPromptSubmit  → ユーザーがプロンプトを送信したとき
PreToolUse        → ツール実行前
PostToolUse       → ツール実行後
Stop              → Claude が応答を止めたとき
```

`~/.claude/settings.json` に設定することで任意のシェルスクリプトを実行できる。

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
  global.md                     # 全PJ共通の設計方針（手動編集）
  repos/
    drone-platform.md           # Claude が自動追記するPJ固有の記憶
    personal-tool.md
```

`global.md` には個人の癖・設計方針のみ書く。コードは書かない。

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

### start.sh（記憶注入）

`UserPromptSubmit` hook で実行される。

```bash
#!/bin/bash
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO=$(basename "$(pwd)")
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
INJECT_MARKER="<!-- claude-memory-sync: auto-generated -->"

# 最新を取得
git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true

# 既存の注入ブロックを削除
sed -i.bak "/$INJECT_MARKER/,\$d" "$CLAUDE_MD" 2>/dev/null || true

# 記憶を注入
{
  echo "$INJECT_MARKER"
  [ -f "$MEMORY_DIR/global.md" ]          && cat "$MEMORY_DIR/global.md"
  [ -f "$MEMORY_DIR/repos/${REPO}.md" ]   && cat "$MEMORY_DIR/repos/${REPO}.md"
} >> "$CLAUDE_MD"
```

既存の注入ブロックをセッションごとに上書きするので肥大化しない。

### stop.sh（自動push）

`Stop` hook で実行される。変更があれば自動コミット・push。

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
- Git・Node.js v18以上
- GitHubのプライベートリポジトリ（記憶保存用）を1つ作成済み

### インストール

```bash
curl -fsSL https://raw.githubusercontent.com/yourname/claude-memory-sync/main/install.sh | bash
```

インストーラが自動でやること：

1. `~/.claude/skills/memory-sync/` に Skill をクローン
2. 記憶リポジトリのGit URLを聞いてクローン
3. `global.md` のテンプレートを配置
4. `~/.claude/settings.json` に hook を登録
5. `cm` コマンドを `~/.local/bin/` にシンボリックリンク
6. グローバル `.gitignore` に `.letta/` を追加

### 別PCへの展開

```bash
# 2台目以降も同じコマンド一発
curl -fsSL https://raw.githubusercontent.com/yourname/claude-memory-sync/main/install.sh | bash
# → 既存の記憶リポジトリURLを入力するだけ
```

## 日常の使い方

### 作業開始

```bash
claude    # いつも通り起動するだけ
```

前提の説明は不要になる。

### 記憶の更新

作業中または終わりに Claude へ一言。

```
今日の知見を記憶して
```

Claude が `~/.claude-memory/repos/{リポジトリ名}.md` に追記し、`Stop` hook で自動push される。

### cm コマンド

```bash
cm            # pull → commit → push
cm status     # 記憶ファイルの一覧と行数を確認
cm edit       # global.md をエディタで開く
cm clean      # ~/.claude/CLAUDE.md の注入ブロックを削除
```

## 複数リポジトリの運用

20リポジトリ並行でも設定は変わらない。

- **個人の癖・設計方針** → `global.md`。全リポジトリで共通
- **PJ固有の文脈** → Claude が自動で `repos/{repo}.md` に分けて記憶

```
drone-platform/ で作業
  → global.md + repos/drone-platform.md が注入される

personal-tool/ で作業
  → global.md + repos/personal-tool.md が注入される
```

ディレクトリを移動するだけで自動切り替え。

## セキュリティ

記憶ファイルには**方針・パターン・禁止事項のみ**を書く。コードは書かない。

- ソースコードは一切Gitに入らない
- 外部に送信されるものは何もない
- プライベートリポジトリで完全に自己管理

## アンインストール

```bash
node ~/.claude/skills/memory-sync/bin/uninstall.js
```

hook の削除と `~/.claude/CLAUDE.md` のクリーンアップを自動で行う。

## まとめ

| 機能 | 実現方法 |
|---|---|
| 記憶の注入 | `UserPromptSubmit` hook → `~/.claude/CLAUDE.md` に書き込み |
| プロジェクト非汚染 | グローバル CLAUDE.md のみを使用 |
| 記憶の永続化 | プライベート Git リポジトリ |
| 複数PC同期 | Git push/pull |
| 複数PJ分離 | `repos/{repo}.md` で自動分岐 |
| インストール | `install.sh` one-liner |

claude-subconscious の考え方に共感しつつ、外部サービスへの依存とコストを排除したかった人に刺さると思う。

リポジトリ → https://github.com/yourname/claude-memory-sync
