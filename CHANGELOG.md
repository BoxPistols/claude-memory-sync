# Changelog

本プロジェクトの変更履歴。[Keep a Changelog](https://keepachangelog.com/) に準拠。

## [Unreleased]

### Fixed

- **新規 `repos/<slug>.md` が初回 sync で commit されない問題** — `bin/cm sync` /
  `hooks/stop.sh` の `git add -- ':(glob)**.md'` がディレクトリ自体 untracked な
  サブディレクトリ配下の `.md` を拾わず、初めて project 固有メモリを作った直後の
  `claude-mem` が「nothing added to commit」で止まっていた。`git add -A -- '*.md'`
  に置換して解決。副次効果として、tracked `.md` の **削除** も auto-commit 対象に
  なる (これまでは手動 `git rm` が必要だった)

### Security (post-v0.1.0 監査で発見・修正)

- **[CRITICAL] プロンプトインジェクション脆弱性修正 (S-3)** — 攻撃者が memory
  repo に偽の `<!-- claude-memory-sync:begin -->` / `:end` マーカーを含む
  global.md を push することで、CLAUDE.md の注入ブロック構造を破壊し、
  攻撃プロンプトを永続的に残留させられる脆弱性を修正。
  `hooks/start.sh` の cat 時に grep -F で注入マーカー行を除去する
  サニタイズを追加し、`hooks/cleanup.sh` の awk を「複数 begin/end を
  まとめて剥がす」ロジックに変更した
- **[HIGH] /tmp symlink 攻撃対策 (S-1 / S-2)** — ログおよびエラー出力の
  保存先を `/tmp/claude-memory-sync*.log` から `~/.claude/logs/` (mode 700)
  に移動。共有システム上での pre-plant symlink による settings.json 書き換え
  や、git pull エラー (URL / 認証情報を含みうる) の情報漏洩を防ぐ
- **[HIGH] settings.json の atomic write (S-7)** — `bin/setup.js` /
  `bin/uninstall.js` が `writeFileSync` で直接上書きしていたのを、
  一時ファイル + `renameSync` (POSIX atomic rename) に変更。install 途中の
  Ctrl+C / disk full / クラッシュで Claude Code の settings.json が
  破損するリスクを排除。ついでに chmod 0600 も設定
- **[HIGH] scan-secrets の history scan 対応 (S-9)** — 以前は未 commit
  差分のみ scan していた。過去セッションで scanner を bypass して secret が
  commit されていた場合、push 時に検出できなかった。`cm sync` の push 前に
  `CLAUDE_MEMORY_SCAN_MODE=history` で `@{u}..HEAD` の diff を scan する
  ように変更
- **[MEDIUM] scan-secrets のパターン追加 (S-10)** — 以下を追加:
  `gho_/ghu_/ghs_/ghr_` (GitHub OAuth/server token 亜種), `ASIA`
  (AWS temporary key), `GOCSPX-` (Google OAuth secret), Azure Storage
  connection string, Slack webhook, `npm_*`, `dckr_pat_*`, `dop_v1_*`,
  `dapi*` (Databricks), `shpat_*` / `shpca_*` (Shopify), `glpat-*`
  (GitLab), `r8_*` (Replicate)
- **[MEDIUM] git index file mode 修正 (S-18)** — `install.sh` /
  `hooks/*.sh` / `bin/cm` を 100644 から 100755 にして、clone 直後から
  executable になるようにした
- **[MEDIUM] install.sh が clone 元 URL を echo で明示 (S-6)** —
  `CLAUDE_MEMORY_SYNC_REPO` が公式以外に設定されている場合は警告を表示
- **[MEDIUM] cleanup.sh の awk 堅牢化** — 1 組目の end で停止せず、全ての
  begin/end マーカー行を除去するロジックに変更。S-3 の構造破壊攻撃への
  深層防御
- **README.md セキュリティセクション大幅拡張** — trust model
  (memory repo collaborator = Claude 操作権限)、組み込みの防御、
  防げない脅威、バイパス方法を明示

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
