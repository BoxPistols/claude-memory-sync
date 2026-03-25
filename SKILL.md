# Memory Sync Skill

Claude Code のセッション間で設計方針・知見を永続化するスキル。
外部サービス不要。Git管理のMarkdownファイルに記憶を保存する。

## 記憶ファイルの場所

- グローバル（全PJ共通）: `~/.claude-memory/global.md`
- プロジェクト固有: `~/.claude-memory/repos/{リポジトリ名}.md`

## セッション開始時の動作

1. `~/.claude-memory/global.md` を読み込む
2. `~/.claude-memory/repos/{repo}.md` が存在すれば読み込む
3. 両ファイルの方針に従って作業する

## 記憶の更新ルール

ユーザーから「記憶を更新して」「今日の知見を保存して」と言われたとき、
または作業の締めくくりに新しいパターンを発見したとき：

- `~/.claude-memory/repos/{repo}.md` に追記する
- **追記のみ**。既存の内容は消さない
- 重複する内容は書かない
- コードは書かない。方針・パターン・禁止事項のみ
- 箇条書き・簡潔に

## global.md に書く内容の例

```markdown
## コンポーネント設計
- 単一責任。1コンポーネント1責務
- Props は必ず型定義。any 禁止

## MUI
- sx の padding/margin は数値のみ（'8px' はNG、1 と書く）
- theme spacing 単位を徹底

## Claude への指示スタイル
- 差分だけ返す。ファイル全体を返さない
- 変更理由を1行コメントで添える
```

## 記憶の同期（複数PC運用）

`cm` コマンドで記憶リポジトリをGit pushする。
作業後に `cm` を叩くだけで全PCに記憶が伝播する。
