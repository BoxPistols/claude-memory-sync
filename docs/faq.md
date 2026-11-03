# FAQ

[README に戻る](../README.md)


## Q. Claude Code 本体のメモリ機能 (`~/.claude/projects/*/memory/`) との違いは?

A. Claude Code 組み込みのメモリはプロジェクトごとにローカル保存されるだけで、**複数 PC 間の同期・Git 履歴・バックアップが無い**。本ツールは同じ問題を Git で解決し、さらに `global.md` (全 PJ 共通) という概念を追加します。両者は併用できます。

## Q. プロジェクト内の `CLAUDE.md` は読まれないの?

A. 読まれます。本ツールが書き込むのは **グローバルの `~/.claude/CLAUDE.md`** と、git 管理外にした **`<project-root>/CLAUDE.local.md`** だけなので、プロジェクトで追跡されている `CLAUDE.md` はそのまま Claude Code が読み込みます。すべて有効です。

## Q. global.md と repos/*.md が両方ある場合、どちらが優先される?

A. global.md は `~/.claude/CLAUDE.md` に、repos/*.md は `<project-root>/CLAUDE.local.md` に注入され、Claude はどちらも読みます。内容が矛盾した場合の動作は未定義です。矛盾しないように書いてください。一般には「global.md は一般方針」「repos/*.md は例外やプロジェクト固有」という切り分けが自然です。

## Q. Claude Code を使わないプロジェクトでも記憶は更新される?

A. `SessionStart` / `Stop` / `SessionEnd` hook は Claude Code を起動したときだけ発火するので、他のエディタ作業中には何も起きません。

## Q. 記憶ファイルに GitHub token や API key を誤って書いてしまった

A. セッション終了時または `cm sync` 実行時にシークレットスキャナが検出して commit を中止します。記憶ファイルから該当行を削除して再実行してください。

もし既に push してしまった場合は、**即座に該当トークンを revoke** して、git history を書き換え (`git filter-repo` など) してください。この場合の対応は本ツールの責務を超えます。

## Q. 20 リポジトリで使いたい

A. 問題ありません。プロジェクト固有の記憶は `repos/{git-remote-slug}.md` に分離され、注入先も `<project-root>/CLAUDE.local.md` とプロジェクトごとに分かれるので、何個でも並行可能です。global.md は全プロジェクトで共有され、`~/.claude/CLAUDE.md` へ注入されます。

> **v0.1.x までの注意**: 以前はプロジェクト固有の記憶も `~/.claude/CLAUDE.md`（全セッション共有）へ注入していました。複数リポジトリで Claude Code を**同時起動**すると後勝ちで上書きされ、別リポジトリの記憶が混入する不具合がありました。現在は注入先を分離して解消しています。

## Q. 別リポジトリが物理的にネストしている場合は？

A. **この 1 パターンだけ、親の記憶が子セッションに読まれます（既知の制限）。**

Claude Code は cwd から親ディレクトリを遡り、各階層の `CLAUDE.md` / `CLAUDE.local.md` を読み込みます（公式ドキュメント: 「checking each directory along the way」）。そのため `/repo-a/repo-b/`（別リポジトリが物理的に内包されている構成）で作業すると、`repo-b` のセッションは `/repo-a/CLAUDE.local.md` も読みます。

これは Claude Code のメモリ読み込み仕様によるもので、本ツール側では回避できません。

**入れ子を解消できるなら、そちらが確実です。** 同じ経路で親の**追跡対象の `CLAUDE.md`**（別プロジェクトの指示そのもの）も読み込まれており、これは記憶ツールとは無関係の問題なので設定では塞ぎきれません。ディレクトリを並列に移せば両方まとめて消えます。

移動できない場合は `claudeMdExcludes` で除外してください。

```json
// .claude/settings.local.json
{
  "claudeMdExcludes": ["**/repo-a/**"]
}
```

`~/.claude/settings.json` / `./.claude/settings.json` / `./.claude/settings.local.json` のいずれでも設定でき、設定層ごとに配列がマージされます。ただし組織のマネージドポリシーで配布された `CLAUDE.md` は除外できません。

> **未確認**: 遡査がファイルシステムのどこまで続くか、`.git` の境界で止まるかは公式ドキュメントに明記がありません。上記は「親ディレクトリを遡る」という記載から導かれる挙動です。

## Q. Windows でも動く?

A. **macOS / Linux 前提**です。`install.sh` と shell hook が POSIX シェルを要求します。WSL2 なら動くはずですが検証していません。

## Q. Zsh じゃなく別のシェルでも動く?

A. `install.sh` の PATH 自動追記プロンプトは zsh / bash を認識します。fish / nushell 等を使っている場合は手動で `~/.local/bin` を PATH に追加してください。フック本体は `/bin/bash` で動くので、ログインシェルが何であれ問題ありません。

## Q. fork して自分で改造したい

A. `CLAUDE_MEMORY_SYNC_REPO` 環境変数を設定して install.sh を実行すると、そのリポジトリから clone します。

```bash
CLAUDE_MEMORY_SYNC_REPO=https://github.com/you/claude-memory-sync-fork \
  ./install.sh
```

または開発中なら `~/.claude/skills/memory-sync` を fork リポジトリへのシンボリックリンクにしても OK です。詳しくは [CONTRIBUTING.md](../CONTRIBUTING.md) を参照。
