# Changelog

本プロジェクトの変更履歴。[Keep a Changelog](https://keepachangelog.com/) に準拠。

## [Unreleased]

## [0.1.0] — 2026-04-11

初回 OSS 公開版。

### Added
- `hooks/scan-secrets.sh` — commit 前に OpenAI / Anthropic / GitHub / AWS / Google / Slack / Stripe / Hugging Face の API キー、JWT、PEM 秘密鍵の典型パターンを検出するシークレットスキャナ
- `bin/cm log` — 最近の commit 10 件を表示するサブコマンド
- `bin/cm status` の ahead/behind 表示、未 commit 変更表示、最終 commit oneline 表示
- `install.sh` の対話モードで `~/.local/bin` を `~/.zshrc` / `~/.bashrc` に自動追記するプロンプト
- `CLAUDE_MEMORY_AUTO_PUSH` — セッション終了時の自動 push を opt-in する環境変数
- `CLAUDE_MEMORY_SKIP_SECRET_SCAN` — シークレットスキャナを一時的にバイパスする環境変数
- `CLAUDE_MEMORY_SYNC_REPO` — install.sh が skill を clone する元 URL を上書きできる環境変数 (fork / 開発用)
- `package.json` — ESM module 宣言と npm メタデータ (`type: module`, `bin`, `engines`, etc.)
- `LICENSE` (MIT)
- `.gitignore`
- `CHANGELOG.md` (本ファイル)
- `CONTRIBUTING.md`

### Changed
- **プロジェクトキー算出を git remote ベースの slug に変更** — 以前の `basename(pwd)` だと同名 basename の別リポジトリが衝突した。HTTPS / SSH どちらの URL 形式でも同一 slug を生成する
- **セッション終了時の自動 push をデフォルト OFF に変更** — 意図しない機密漏洩を防ぐ。`CLAUDE_MEMORY_AUTO_PUSH=1` で従来動作に戻せる
- **CLAUDE.md 注入ブロックを begin/end マーカー形式に変更** — `<!-- claude-memory-sync:begin -->` 〜 `<!-- claude-memory-sync:end -->` で sandwich することで、ユーザーの手書きコンテンツとの境界が明示される
- **`bin/cm sync` を `pull --rebase` に変更** — 以前の `pull --ff-only` は競合時に黙殺されていた。失敗時は明示的にエラー出力してユーザーに対処を促す
- **hook 重複検知をマーカープロパティベースに変更** — 以前は command 文字列の substring match だった。`_claude_memory_sync: true` を付けて登録することで、同名の別 hook と干渉しない
- **`hooks/start.sh` / `hooks/cleanup.sh` のブロック削除ロジックを sed から awk ベースに変更** — 固定文字列マッチで fragile さを解消
- **`install.sh` の出力から絵文字を除去** — git / GitHub artifacts 内の絵文字排除ポリシーに揃えた
- **`bin/uninstall.js` を `execFileSync` に変更** — `exec` 呼び出しを避けてシェル解釈を挟まないようにした
- `SKILL.md` / `README.md` / `zenn-article.md` を新動作に合わせて全面更新

### Removed
- `install.sh` が `.letta/` をグローバル `.gitignore` に追加していた処理 — 本プロジェクトと無関係だったため削除
- 旧式の `<!-- claude-memory-sync: auto-generated -->` 単一マーカー方式 (後方互換は `cleanup.sh` で維持)

### Fixed
- `bin/setup.js` / `bin/uninstall.js` が `import` 構文を使っているのに `package.json` が無く、Node 18 / 20 で `SyntaxError` になっていた
- 謎の空ディレクトリ `{hooks,bin,template}` (shell expansion 失敗の残骸) を削除
- `hooks/start.sh` の pull 失敗が完全に黙殺されていた問題を修正 — `/tmp/claude-memory-sync.log` にログを残すようにした

[Unreleased]: https://github.com/BoxPistols/claude-memory-sync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/BoxPistols/claude-memory-sync/releases/tag/v0.1.0
