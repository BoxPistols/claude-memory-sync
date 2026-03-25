# claude-memory-sync

Claude Code にセッション間の記憶を持たせる Claude Code Skill。

外部サービス不要・コストゼロ・完全自己管理。

## 特徴

- **Git管理** — 記憶はプライベートGitリポジトリで管理。完全にあなたのもの
- **複数PC対応** — どのMacからでも同じ記憶が使える
- **複数リポジトリ対応** — グローバル方針 + プロジェクト固有の記憶を自動で合成
- **自動注入** — Claude Code 起動時に記憶が自動で CLAUDE.md に注入される
- **自動同期** — セッション終了時に記憶が自動でpushされる

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

## 使い方

```bash
claude          # いつも通り起動するだけ。記憶が自動注入される
memory              # 記憶を手動でGit同期（複数PC運用時）
```

作業中に Claudeへ一言：

```
今日の知見を記憶して
```

これだけで `~/.claude-memory/repos/{リポジトリ名}.md` に追記される。

## 記憶ファイルの構造

```
~/.claude-memory/
  global.md          # 全PJ共通の設計方針・癖
  repos/
    project-a.md     # project-a 固有の記憶
    project-b.md     # project-b 固有の記憶
```

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

## License

MIT
