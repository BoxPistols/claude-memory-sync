# トラブルシューティング

[README に戻る](../README.md)


## `cm: command not found`

インストール時に `~/.local/bin` が PATH に入っていません。

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # zsh の場合
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # bash の場合
source ~/.zshrc   # または新しいターミナルを開く
```

## 記憶が Claude に注入されていない気がする

まず手動で確認:

```bash
cat ~/.claude/CLAUDE.md        # global.md の注入先
cat ./CLAUDE.local.md          # プロジェクト固有の記憶の注入先 (プロジェクト直下で)
```

`<!-- claude-memory-sync:begin -->` から `:end -->` までのブロックがあればインジェクションは成功しています。`CLAUDE.md` は `SessionStart` hook より先に読み込まれるため、書き換えた内容が効くのは次のセッションからです。

もしブロックが無い場合:

```bash
# hook が登録されているか確認
cat ~/.claude/settings.json | grep -A 3 SessionStart

# 手動で start.sh を実行してみる
bash ~/.claude/skills/memory-sync/hooks/start.sh
```

それでも動かない場合は `~/.claude/logs/claude-memory-sync.log` を見てみてください。

## `cm sync` で pull が失敗する

リモートと分岐している可能性があります。

```bash
cd ~/.claude-memory
git status        # 未コミットの変更があるか確認
git log --oneline -5
git fetch
git log origin/main --oneline -5
```

手動で `git pull --rebase` して競合を解決してから、もう一度 `cm sync`。

## scan-secrets が誤検出している (正当な内容が block された)

一時的にバイパスするには:

```bash
CLAUDE_MEMORY_SKIP_SECRET_SCAN=1 cm sync
```

ただし、本当に機密情報が紛れていないかは必ず自分で確認してください。

## hook が自分の別の hook と衝突している / 消えた

本ツールはマーカー (`_claude_memory_sync: true`) 付きで hook を登録するため、同イベントに別の hook があっても干渉しません。逆に本ツール以外の hook が壊れている場合は、本ツールとは無関係の問題です。

## アンインストール後に記憶が残っている

それは意図通りです。`~/.claude-memory/` は `uninstall.js` では削除されません。

```bash
rm -rf ~/.claude-memory   # 完全削除
```

## 既存の `~/.claude/CLAUDE.md` を壊しそうで怖い

手書きのコンテンツは絶対に触らないので大丈夫ですが、念のため:

```bash
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.backup
```

でバックアップを取ってから始めることをおすすめします。
