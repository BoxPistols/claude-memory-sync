# claude-memory-sync

Claude Code にセッション間の記憶を持たせる Claude Code Skill。

外部サービス不要・コストゼロ・完全自己管理。

## 特徴

- **Git管理** — 記憶はプライベートGitリポジトリで管理。完全にあなたのもの
- **複数PC対応** — どのMacからでも同じ記憶が使える
- **複数リポジトリ対応** — グローバル方針 + プロジェクト固有の記憶を自動で合成
- **自動注入** — Claude Code 起動時に記憶が自動で CLAUDE.md に注入される
- **自動同期** — セッション終了時に記憶が自動でpushされる

## 前提

- Claude Code がインストール済み
- Git / Node.js（v18以上）が使える

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

途中で記憶リポジトリのGit URLを聞かれる。複数PCで同期したい場合はGitHubのプライベートリポジトリURLを入力。ローカルのみなら空Enterでスキップ。

## 使い方

インストール後は **どのリポジトリでも追加設定不要**。`claude` を起動するだけで記憶が自動注入される。

```bash
cd ~/dev/any-project
claude          # global.md + repos/any-project.md が自動で CLAUDE.md に注入される
```

### プロジェクト固有の記憶を育てる

作業中に Claude へ一言：

```
今日の知見を ~/.claude-memory/repos/any-project.md に記憶して
```

次回以降、そのプロジェクトでは自動で読み込まれる。

### 手動で記憶を同期（複数PC運用時）

```bash
memory          # pull → commit → push
```

## 仕組み

hook が `~/.claude/settings.json` にグローバル登録される。どのディレクトリで `claude` を起動しても自動で発火する。

| タイミング | hook | 動作 |
|---|---|---|
| セッション開始 | `UserPromptSubmit` | `global.md` + `repos/{repo}.md` を `CLAUDE.md` に注入 |
| セッション終了 | `Stop` | 記憶リポジトリを自動 commit & push |

## 記憶ファイルの構造

```
~/.claude-memory/            ← プライベートGitリポジトリ（記憶データ）
  global.md                  # 全PJ共通の設計方針・癖
  repos/
    project-a.md             # project-a 固有の記憶
    project-b.md             # project-b 固有の記憶
```

`global.md` にはコードではなく **方針・パターン・禁止事項** を書く。

## 複数PCでの運用

```bash
# 別PCでの初回セットアップ（同じコマンド）
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
# → 既存の記憶リポジトリURLを入力するだけ
```

## 環境変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `CLAUDE_MEMORY_DIR` | 記憶リポジトリの場所 | `~/.claude-memory` |

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `memory` コマンドが見つからない | `export PATH="$HOME/.local/bin:$PATH"` を `~/.zshrc` に追加 |
| `setup.js` でエラー | Node.js v18以上か確認（`node --version`） |
| hook が発火しない | Claude Code を最新版に更新 |

## License

MIT
