# claude-memory-sync

Claude Code にセッション間の記憶を持たせる Claude Code Skill。

**外部サービス不要・コストゼロ・完全自己管理。**

## 特徴

- **プロジェクトを汚さない** — 注入先は `~/.claude/CLAUDE.md`（グローバル）のみ
- **Git管理** — 記憶はプライベートGitリポジトリで管理。完全にあなたのもの
- **複数PC対応** — どのMacからでも同じ記憶が使える
- **複数リポジトリ対応** — グローバル方針 + プロジェクト固有の記憶を自動で合成
- **自動注入** — `UserPromptSubmit` hook で記憶が自動注入される
- **自動同期** — `Stop` hook でセッション終了時に自動push

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

## 使い方

```bash
claude        # いつも通り起動するだけ。記憶が自動注入される

cm            # 記憶を手動でGit同期（pull → commit → push）
cm status     # 記憶ファイルの一覧と状態を確認
cm edit       # global.md をエディタで開く
cm clean      # ~/.claude/CLAUDE.md の注入ブロックを削除
```

作業中に Claude へ一言：

```
今日の知見を記憶して
```

`~/.claude-memory/repos/{リポジトリ名}.md` に自動追記される。

## 記憶ファイルの構造

```
~/.claude-memory/
  global.md          # 全PJ共通の設計方針・癖（手動編集）
  repos/
    project-a.md     # Claude が自動追記するPJ固有の記憶
    project-b.md
```

## 注入の仕組み

`~/.claude/CLAUDE.md`（グローバル）にのみ書き込む。

```
~/.claude/CLAUDE.md
  ├── （手書きの内容があればそのまま残る）
  └── <!-- claude-memory-sync: auto-generated -->
        ├── global.md の内容
        └── repos/{repo}.md の内容（あれば）
```

プロジェクト内の `CLAUDE.md` には一切手を加えない。

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

## アンインストール

```bash
node ~/.claude/skills/memory-sync/bin/uninstall.js
```

hook の削除・`~/.claude/CLAUDE.md` のクリーンアップを自動で行う。
記憶リポジトリ（`~/.claude-memory`）は削除されない。

## License

MIT
