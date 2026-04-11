# Memory Sync Skill

Claude Code のセッション間で設計方針・知見を永続化するスキル。
外部サービス不要。Git 管理の Markdown ファイルに記憶を保存する。

## 記憶ファイルの場所

- **グローバル (全 PJ 共通)**: `~/.claude-memory/global.md`
- **プロジェクト固有**: `~/.claude-memory/repos/{project-key}.md`

`{project-key}` は現在ディレクトリから自動決定される:

1. `git remote get-url origin` が取れたら、ホスト + owner + repo を slug 化 (例: `github.com-BoxPistols-claude-memory-sync`)
2. 取れなければ `git rev-parse --show-toplevel` の basename
3. どちらも失敗したら現在ディレクトリの basename

同じ basename でも Git リモートが異なれば別プロジェクトとして扱われる。

## セッション開始時の動作

1. 記憶リポジトリが Git 管理であれば `git pull --ff-only` を試行 (失敗しても続行、`/tmp/claude-memory-sync.log` にログ)
2. `~/.claude-memory/global.md` を読み込む
3. `~/.claude-memory/repos/{project-key}.md` が存在すれば読み込む
4. 両方を `~/.claude/CLAUDE.md` の末尾に `<!-- claude-memory-sync:begin -->` 〜 `<!-- claude-memory-sync:end -->` マーカーで包んで注入
5. プロジェクト内の `CLAUDE.md` には一切書かない

## セッション終了時の動作

1. 記憶リポジトリに変更があるかチェック (なければ終了)
2. **シークレットスキャナ** で変更内容をチェック (`sk-`, `ghp_`, `AKIA`, JWT, PEM 等のパターン)
3. 問題がなければ `git commit`
4. `CLAUDE_MEMORY_AUTO_PUSH=1` が設定されていれば自動 push。**デフォルトでは push しない**

デフォルトで push を無効化しているのは、Claude が誤って API キーや機密情報を記憶ファイルに書き込んだとき、意図せずリモートへ漏洩することを避けるため。push は `cm` コマンドで明示的に行うことを推奨する。

## 記憶の更新ルール

ユーザーから「記憶を更新して」「今日の知見を保存して」と言われたとき、
または作業の締めくくりに新しいパターンを発見したとき:

- `~/.claude-memory/repos/{project-key}.md` に追記する
- **追記のみ**。既存の内容は消さない
- 重複する内容は書かない
- コードは書かない。方針・パターン・禁止事項のみ
- 箇条書き・簡潔に

## global.md に書く内容の例

```markdown
## コンポーネント設計
- 単一責任。1 コンポーネント 1 責務
- Props は必ず型定義。any 禁止

## Claude への指示スタイル
- 差分だけ返す。ファイル全体を返さない
- 変更理由を 1 行コメントで添える
```

## 記憶の同期 (複数 PC 運用)

`cm` コマンドで記憶リポジトリを Git pull / push する。

```bash
cm         # pull → commit → push (push は確認あり)
cm status  # ファイル一覧 + ahead/behind 表示
cm edit    # global.md をエディタで開く
cm clean   # ~/.claude/CLAUDE.md から注入ブロックを削除
```

作業後に `cm` を叩くだけで全 PC に記憶が伝播する。
