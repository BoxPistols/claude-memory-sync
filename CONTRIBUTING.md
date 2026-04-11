# Contributing

claude-memory-sync への貢献方法。

## バグ報告 / 機能提案

[Issues](https://github.com/BoxPistols/claude-memory-sync/issues) に投稿してください。以下の情報が揃っていると調査が速いです:

- macOS / Linux など OS と version
- `node --version` と `git --version`
- 発生した現象と期待していた動作
- 再現手順
- 該当すれば `/tmp/claude-memory-sync.log` の内容

## 開発セットアップ

```bash
git clone git@github.com:BoxPistols/claude-memory-sync.git
cd claude-memory-sync

# ローカル install (既存の installed skill を上書きする点に注意)
CLAUDE_MEMORY_SYNC_REPO="$(pwd)" ./install.sh
```

開発中の skill を直接読み込ませたい場合は、`~/.claude/skills/memory-sync` を本リポジトリへのシンボリックリンクにしておくと楽です。

```bash
rm -rf ~/.claude/skills/memory-sync
ln -s "$(pwd)" ~/.claude/skills/memory-sync
```

## テスト

ユニットテストはまだありません。以下を手動で通してから PR を出してください:

```bash
# shellcheck (install: brew install shellcheck)
shellcheck install.sh hooks/*.sh bin/cm

# node scripts の構文チェック
node --check bin/setup.js
node --check bin/uninstall.js

# scan-secrets の動作確認
CLAUDE_MEMORY_DIR=/tmp/test-mem bash hooks/scan-secrets.sh
```

## コミットメッセージ規約

[Conventional Commits](https://www.conventionalcommits.org/) に準拠。

- `feat:` 新機能
- `fix:` バグ修正
- `docs:` ドキュメント
- `refactor:` 挙動を変えないリファクタ
- `test:` テスト追加・修正
- `chore:` ビルドスクリプト・補助ツール類

例:

```
feat(hooks): scan-secrets に Stripe key のパターンを追加

sk_live_ と rk_live_ の両方を検出できるようにした。
```

日本語本文で OK です。

## ブランチとプルリクエスト

- `main` ブランチへの直接 push は避け、短命な feature ブランチを切って PR を出してください
- PR の本文には動機と影響範囲を簡潔に書いてください
- レビューの往復を減らすため、`shellcheck` と `node --check` をローカルで通してから push してください

## セキュリティ上の注意

本ツールは **シークレットの誤 commit を防ぐことを目的の一つ**にしています。`hooks/scan-secrets.sh` にパターンを追加する変更は歓迎です。ただし:

- 実在するシークレット文字列をテスト fixture としてリポジトリに入れないこと (fake 文字列を使うこと)
- `grep -E` の正規表現が BSD grep でも GNU grep でも動くことを確認すること
- 誤検出率が跳ね上がらないよう、パターンは十分に specific にすること

## License

コントリビュートしたコードは [MIT License](./LICENSE) の下で公開されることに同意いただきます。
