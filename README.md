# claude-memory-sync

Claude Code にセッション間の記憶を持たせる自作メモリ層。**外部サービス不要・コストゼロ・Git で完全自己管理。**

[![CI](https://github.com/BoxPistols/claude-memory-sync/actions/workflows/ci.yml/badge.svg)](https://github.com/BoxPistols/claude-memory-sync/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

## TL;DR

毎回 Claude Code に「MUI の sx は px 禁止」「pnpm を使う」などを言い直していませんか?
このツールを入れると、そういう方針を `~/.claude-memory/global.md` に書いておくだけで、**次回起動時から Claude Code が自動的に覚えています**。プロジェクトごとの文脈は `repos/{project-key}.md` に分かれて保存され、ディレクトリを移動するだけで切り替わります。

記憶はあなた自身のプライベート Git リポジトリ上にあるので、**外部サービスにソースコードが送信されることは一切ありません**。複数 PC でも `git push/pull` で同期できます。

---

## もくじ

- [TL;DR](#tldr)
- [何を解決するか (before / after)](#何を解決するか-before--after)
- [アーキテクチャ](#アーキテクチャ)
- [特徴](#特徴)
- [Getting Started (5 分)](#getting-started-5-分)
- [日常の使い方](#日常の使い方)
- [記憶ファイルの書き方](#記憶ファイルの書き方)
- [注入の仕組み](#注入の仕組み)
- [複数 PC 運用](#複数-pc-運用)
- [セキュリティ](#セキュリティ)
- [トラブルシューティング](#トラブルシューティング)
- [FAQ](#faq)
- [環境変数](#環境変数)
- [アンインストール](#アンインストール)
- [コントリビューション](#コントリビューション)
- [License](#license)

---

## 何を解決するか (before / after)

### Before

```
あなた: 「このコンポーネントに sx で padding 追加して」
Claude: 「sx={{ padding: '16px' }} で追加しました」
あなた: 「いや、px じゃなく spacing 単位で。前も言ったよね」
Claude: 「申し訳ない。sx={{ padding: 2 }} に修正します」

— 翌日 —
あなた: 「この Button に margin 足して」
Claude: 「sx={{ margin: '8px' }} に...」
あなた: 😩
```

### After (claude-memory-sync を入れた後)

```
# 最初に 1 度だけ書く:
# ~/.claude-memory/global.md
# ## MUI
# - sx の padding/margin は数値のみ (px 禁止、spacing 単位で)

あなた: 「このコンポーネントに sx で padding 追加して」
Claude: 「sx={{ padding: 2 }} で追加しました」

あなた: 😊
```

Claude Code は毎セッション開始時にこの記憶を自動で読み込みます。指示し直す必要はありません。

---

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│  あなたの Mac                                                 │
│                                                                │
│  ┌──────────────────────┐                                    │
│  │  ~/.claude-memory/   │ ← あなた専用のプライベート         │
│  │  (Git リポジトリ)     │   Git リポジトリ (GitHub等)        │
│  │                      │                                    │
│  │  global.md           │ ← 全 PJ 共通の方針 (手動編集)       │
│  │  repos/              │                                    │
│  │    github.com-you-   │ ← PJ 固有の記憶 (Claude が追記)     │
│  │      project-a.md    │                                    │
│  │    github.com-you-   │                                    │
│  │      project-b.md    │                                    │
│  └──────────┬───────────┘                                    │
│             │                                                  │
│             │  UserPromptSubmit hook                           │
│             │  (cd 先の git remote URL に応じて自動切替)       │
│             ▼                                                  │
│  ┌──────────────────────┐                                    │
│  │ ~/.claude/CLAUDE.md  │ ← グローバル CLAUDE.md に注入       │
│  │  (手書きの内容…)     │                                    │
│  │  <!-- cms:begin -->  │ ← begin/end マーカーで sandwich     │
│  │  (global.md の内容)  │                                    │
│  │  (repos/*.md の内容) │                                    │
│  │  <!-- cms:end -->    │                                    │
│  └──────────┬───────────┘                                    │
│             │                                                  │
│             ▼                                                  │
│        Claude Code                                             │
│        (毎セッション、この記憶を読んでから動作)                 │
└──────────────────────────────────────────────────────────────┘

  プロジェクト内の CLAUDE.md には一切書きません。
  OSS リポジトリを汚しません。
```

### 設計上の決めごと

- **プロジェクトを汚さない**: 注入先は `~/.claude/CLAUDE.md` (グローバル) のみ。リポジトリ内の `CLAUDE.md` は触らないので、OSS / チーム共有リポジトリでも安全
- **記憶は Git 管理**: プライベート Git リポジトリに置くので、バックアップ・履歴・複数 PC 同期が全て Git の仕組みで完結
- **自動 push はデフォルト OFF**: Claude が誤って API キー等を書き込んだ場合にリモートへ漏洩しないよう、push は `cm` コマンドで明示的に実行することを推奨
- **シークレットスキャナ内蔵**: commit 前に `sk-*`, `ghp_*`, `AWS AKIA*`, JWT, PEM 等の典型パターンを検出

---

## 特徴

- ✨ **プロジェクトを汚さない** — 注入先は `~/.claude/CLAUDE.md` のみ
- 🔒 **外部サービス不要** — 全ての記憶はあなた自身の Git リポジトリに
- 💻 **複数 PC 対応** — `cm` コマンドで git pull / push するだけ
- 📁 **複数リポジトリ対応** — ディレクトリごとに記憶を自動切替
- 🎯 **プロジェクト衝突回避** — git remote URL ベースの slug で識別
- 🛡️ **シークレットスキャナ内蔵** — API キー / 秘密鍵の誤 commit を防ぐ
- 🟢 **opt-in な自動 push** — 意図しないリモート反映を防止
- 🧹 **クリーンなアンインストール** — 自分が登録した hook だけを削除

(上記は機能要約です。実装の詳細は [CHANGELOG.md](./CHANGELOG.md) を参照)

---

## Getting Started (5 分)

初めて使う人向けのステップバイステップです。

### Step 0. 前提の確認

以下がインストール済みであることを確認してください。

```bash
# Claude Code (公式): https://claude.ai/code
claude --version     # インストール確認

# Git と Node.js v18 以上
git --version
node --version       # v18.0.0 以上
```

もし Claude Code をまだ入れていない場合は、先に [公式サイト](https://claude.ai/code) からインストールしてください。

### Step 1. 記憶保存用のプライベート Git リポジトリを作成

あなた専用の記憶を保存するための**プライベート**リポジトリを GitHub に作ります。既存のメインのリポジトリとは別に、新規で 1 つ作ってください。

**GitHub CLI で作る場合 (推奨):**

```bash
gh repo create claude-memory-private --private --clone=false \
  --description "My personal Claude Code memory"
# → git@github.com:あなたのユーザー名/claude-memory-private.git
```

**Web UI で作る場合:**

1. https://github.com/new を開く
2. Repository name: `claude-memory-private` (名前は任意)
3. **Visibility: Private** を必ず選択
4. README/gitignore/license は全て不要 (空の repo にする)
5. Create → 表示される URL (例: `git@github.com:you/claude-memory-private.git`) をコピー

> **重要**: 必ず **Private** にしてください。public だと全世界があなたの設計方針を見られます。

### Step 2. claude-memory-sync をインストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

インストーラは対話で以下を聞いてきます:

```
Git URL: ← Step 1 でコピーした URL を貼る
```

(空 Enter でローカルのみ運用も可能です。後から `git remote add` で追加できます。)

さらに `~/.local/bin` が PATH に無い場合は `~/.zshrc` / `~/.bashrc` への追記を聞いてきます。`y` で OK。

### Step 3. 最初の記憶を書く

```bash
cm edit
```

エディタ (`$EDITOR` / nano / vim) が開くので、あなたの好みを書きます:

```markdown
# グローバル設計方針

## Claude への指示スタイル
- 差分だけ返す。ファイル全体を返さない
- 変更理由を 1 行コメントで添える

## 禁止事項
- any 型の使用
- console.log の commit
```

保存して終了。

### Step 4. 同期する

```bash
cm sync
```

初回は pull → commit → push を実行。Step 1 で指定したプライベート repo に保存されます。

```bash
cm status
```

で状態を確認できます。

### Step 5. Claude Code を起動して動作確認

```bash
claude
```

起動すると `~/.claude/CLAUDE.md` に Step 3 で書いた方針が自動注入されます。試しに何か頼んでみて、記憶が効いているか確認してください。

**確認の小ネタ**: Claude に「今ロードされているメモリを要約して」と聞くと、注入内容が見えます。

### Step 6. プロジェクト固有の記憶を溜める

プロジェクトで作業中、学んだことを Claude に伝えると記憶してくれます:

```
あなた: このプロジェクトは pnpm を使う。npm は使わない。これ記憶して
Claude: 記憶しました。~/.claude-memory/repos/github.com-you-project-a.md に追記しました。
```

この記憶はセッション終了時に自動 commit されます (**push はされません** — 安全のため)。push したい時は `cm` を実行。

---

## 日常の使い方

```bash
claude                 # いつも通り起動するだけ。記憶が自動注入される

# 作業中に…
あなた: 今日学んだことを記憶して
Claude: ~/.claude-memory/repos/{project-key}.md に追記しました

# セッション終了時
→ 自動 commit (push はされない)

# 複数 PC に同期したい時、または区切りで
cm                     # pull --rebase → secret scan → commit → push
```

### `cm` コマンドリファレンス

| コマンド | 説明 |
|---|---|
| `cm` または `cm sync` | pull --rebase → scan-secrets → commit → push |
| `cm status` | ファイル一覧 + ahead/behind + 未 commit 変更 + 最終 commit |
| `cm log` | 最近の commit 10 件 |
| `cm edit` | `global.md` を `$EDITOR` で開く |
| `cm clean` | `~/.claude/CLAUDE.md` から注入ブロックを削除 (再インストール時など) |
| `cm --help` | ヘルプ表示 |

---

## 記憶ファイルの書き方

記憶ファイルの構造:

```
~/.claude-memory/
├── global.md                              # 全 PJ 共通の設計方針 (手動編集)
└── repos/
    ├── github.com-you-project-a.md        # Claude が自動追記する PJ 固有の記憶
    ├── github.com-you-project-b.md
    └── gitlab.com-you-internal-tool.md
```

ファイル名は **git remote origin URL を slug 化**したもので、以下の順で決定されます:

1. `git remote get-url origin` が取れたら → `github.com-owner-repo` 形式の slug (HTTPS / SSH どちらでも同じ結果)
2. 取れなければ → `git rev-parse --show-toplevel` の basename
3. git リポジトリでなければ → 現在ディレクトリの basename

同じ `project-a` という basename でも remote が違えば別ファイルとして管理されます。

### `global.md` に書くべきこと (全プロジェクトで共通)

- 自分のコーディングスタイル / 命名規則
- 普遍的に使うツール (pnpm 派 / npm 派、tabs vs spaces 等)
- Claude への指示スタイル (差分だけ欲しい、長い説明は不要 等)
- 絶対に使ってほしくないパターン (any 型禁止、console.log commit 禁止 等)

### `repos/*.md` に書くべきこと (プロジェクト固有)

- そのプロジェクト特有の制約 (「この repo は Node 18、新機能は使えない」等)
- 過去の意思決定の背景 (「なぜ X ではなく Y を選んだか」)
- ファイル配置のクセ
- デバッグで見つかった罠

### 書かない方がいいこと

- **コード本体** — メモリはあくまで方針・パターン用。Claude は読みますが、長大なコードは session context を圧迫します
- **API キー / トークン / 秘密鍵** — シークレットスキャナが検出して commit をブロックします
- **機密情報** — プライベート repo でもバックアップが流出する想定を常に持つ

---

## 注入の仕組み

`~/.claude/CLAUDE.md` (グローバル) にのみ書き込みます。プロジェクト内の `CLAUDE.md` には一切触りません。

```
~/.claude/CLAUDE.md
  (あなたの手書きコンテンツ — そのまま残る)
  <!-- claude-memory-sync:begin -->
    ## グローバル設計方針
    (global.md の内容)
    ## プロジェクト固有の記憶 (github.com-you-project-a)
    (repos/github.com-you-project-a.md の内容)
  <!-- claude-memory-sync:end -->
```

`begin` / `end` マーカーで sandwich されているので、セッション開始ごとにブロック内だけが再生成されます。ユーザーの手書きコンテンツは上書きされません。

### セッション終了時の動作

`Stop` hook は以下の順で動きます:

1. 記憶リポジトリに変更があるかチェック (なければ終了)
2. **シークレットスキャナ**で変更内容を検査。API キー / 秘密鍵の典型パターンにマッチしたら commit を中止
3. 問題がなければ `git commit`
4. `CLAUDE_MEMORY_AUTO_PUSH=1` が設定されていれば自動 push (デフォルト: **off**)

push がデフォルト off なのは、Claude が誤って API キーを記憶ファイルに書き込んだときに意図せずリモートへ漏洩することを避けるため。日常的な push は `cm` を明示的に実行することを推奨します。

---

## 複数 PC 運用

2 台目以降は `install.sh` を同じコマンドで実行して、Step 1 で作った**同じ URL**を入力するだけ。

```bash
# 2 台目の Mac
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
# Git URL: git@github.com:you/claude-memory-private.git  ← 1 台目と同じ URL
```

あとは両方の PC で `cm` を叩くと git push/pull で同期されます。`cm status` で ahead/behind を確認可能。

### 同期のタイミング

- **セッション開始時**: `git pull --ff-only` で最新を自動取得 (失敗は `/tmp/claude-memory-sync.log` に記録)
- **セッション終了時**: `git commit` (push はデフォルト off)
- **手動**: `cm` で pull → commit → push を明示実行

### 競合した場合

異なる PC で同じファイルを編集して競合したら、`cm` が `pull --rebase` で取り込みを試みます。自動解決できない場合は明示的なエラーで止まり、手動で解決するよう促します (以前の `pull --ff-only` + 黙殺とは違います)。

---

## セキュリティ

### 信頼モデル (必読)

本ツールは以下の前提で動きます:

1. **memory リポジトリに書き込める人 = あなたの Claude Code の振る舞いを実質的に操作できる人**です。memory repo の内容は `~/.claude/CLAUDE.md` に注入され、Claude Code の全セッションのプロンプトになります。プロンプトインジェクションで情報漏洩・不正指示を仕込むことが可能です
2. したがって memory repo は **必ず private** にしてください。public にすると全世界がコンテンツを見られるだけでなく、PR 経由であなたの CLAUDE.md に任意のプロンプトを仕込まれる可能性があります
3. **collaborator 権限を与える相手は慎重に選んで**ください。信頼できない相手に write 権限を与えるのは、あなたの Claude セッションを渡すのと等価です
4. `~/.claude/skills/memory-sync/hooks/*.sh` を上書きできる人 (= あなたのホームディレクトリに書き込める人) は、セッション開始のたびに任意コードを実行できます。**ホームディレクトリのパーミッションを 700 / 750 に保って**ください

### 組み込みの防御

- **シークレットスキャナ**が commit 前と push 前 (未 push 履歴) の両方を scan します
- 検出パターン (v0.1.0):
  - OpenAI / Anthropic: `sk-*` / `sk_live_*`
  - GitHub: `ghp_*` / `gho_*` / `ghu_*` / `ghs_*` / `ghr_*` / `github_pat_*`
  - AWS: `AKIA*` / `ASIA*`
  - Google: `AIza*` / `GOCSPX-*`
  - Azure: `DefaultEndpointsProtocol=...AccountKey=...`
  - Slack: `xox[baprs]-*` / webhook `T.../B.../*`
  - Stripe: `sk_live_*` / `rk_live_*`
  - npm: `npm_*`
  - Docker Hub: `dckr_pat_*`
  - DigitalOcean: `dop_v1_*`
  - Databricks: `dapi*`
  - Shopify: `shpat_*` / `shpca_*`
  - GitLab: `glpat-*`
  - Hugging Face: `hf_*`
  - Replicate: `r8_*`
  - JWT (3 セグメント形式)
  - PEM private key ブロック
- **入力サニタイズ**: memory ファイル内に偽の `<!-- claude-memory-sync:begin -->` / `:end` マーカーが混入していても、注入時に grep で除去されるので CLAUDE.md の構造が破壊されない (プロンプトインジェクションでの永続汚染を防止)
- **マーカー付き hook 管理**: `_claude_memory_sync: true` プロパティで本ツール所有の hook を識別。他の hook と衝突しない、誤って壊さない
- **Atomic settings.json 書き込み**: 一時ファイル + rename で、install 途中のクラッシュでも `~/.claude/settings.json` を破損させない
- **ログは自ユーザ領域に**: pull 失敗などのログは `~/.claude/logs/` 以下 (mode 700) に保存。`/tmp` 経由の symlink 攻撃や情報漏洩を避ける

### 組み込みで防げないもの

- **memory repo に collaborator として書き込める攻撃者**: 上記信頼モデルの通り、これはツールの守備範囲外です。collaborator 管理を慎重に
- **本スキャナのパターン漏れ**: best-effort です。カスタムのシークレット形式、長期的な keyスキーマ変更、難読化された秘密情報は検出できません。真剣な検査には [trufflehog](https://github.com/trufflesecurity/trufflehog) / [gitleaks](https://github.com/gitleaks/gitleaks) を併用してください
- **MITM at install time**: `curl | bash` でインストールするので、TLS が破られたら任意コードが実行されます。これを避けたい場合は手動 clone + 確認後に `./install.sh` を実行してください

### バイパス

一時的な解除手段:

```bash
CLAUDE_MEMORY_SKIP_SECRET_SCAN=1 cm     # シークレットスキャナをバイパス
CLAUDE_MEMORY_AUTO_PUSH=1 claude        # セッション終了時に自動 push する
```

後者は危険 (push 前に人間が確認できない) なので、**信頼できる環境でのみ** 使ってください。

---

## トラブルシューティング

### `cm: command not found`

インストール時に `~/.local/bin` が PATH に入っていません。

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # zsh の場合
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # bash の場合
source ~/.zshrc   # または新しいターミナルを開く
```

### 記憶が Claude に注入されていない気がする

まず手動で確認:

```bash
cat ~/.claude/CLAUDE.md
```

`<!-- claude-memory-sync:begin -->` から `:end -->` までのブロックがあればインジェクションは成功しています。

もしブロックが無い場合:

```bash
# hook が登録されているか確認
cat ~/.claude/settings.json | grep -A 3 UserPromptSubmit

# 手動で start.sh を実行してみる
bash ~/.claude/skills/memory-sync/hooks/start.sh
```

それでも動かない場合は `/tmp/claude-memory-sync.log` を見てみてください。

### `cm sync` で pull が失敗する

リモートと分岐している可能性があります。

```bash
cd ~/.claude-memory
git status        # 未コミットの変更があるか確認
git log --oneline -5
git fetch
git log origin/main --oneline -5
```

手動で `git pull --rebase` して競合を解決してから、もう一度 `cm sync`。

### scan-secrets が誤検出している (正当な内容が block された)

一時的にバイパスするには:

```bash
CLAUDE_MEMORY_SKIP_SECRET_SCAN=1 cm sync
```

ただし、本当に機密情報が紛れていないかは必ず自分で確認してください。

### hook が自分の別の hook と衝突している / 消えた

本ツールはマーカー (`_claude_memory_sync: true`) 付きで hook を登録するため、同イベントに別の hook があっても干渉しません。逆に本ツール以外の hook が壊れている場合は、本ツールとは無関係の問題です。

### アンインストール後に記憶が残っている

それは意図通りです。`~/.claude-memory/` は `uninstall.js` では削除されません。

```bash
rm -rf ~/.claude-memory   # 完全削除
```

### 既存の `~/.claude/CLAUDE.md` を壊しそうで怖い

手書きのコンテンツは絶対に触らないので大丈夫ですが、念のため:

```bash
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.backup
```

でバックアップを取ってから始めることをおすすめします。

---

## FAQ

### Q. Claude Code 本体のメモリ機能 (`~/.claude/projects/*/memory/`) との違いは?

A. Claude Code 組み込みのメモリはプロジェクトごとにローカル保存されるだけで、**複数 PC 間の同期・Git 履歴・バックアップが無い**。本ツールは同じ問題を Git で解決し、さらに `global.md` (全 PJ 共通) という概念を追加します。両者は併用できます。

### Q. プロジェクト内の `CLAUDE.md` は読まれないの?

A. 読まれます。本ツールが触るのは **グローバルの `~/.claude/CLAUDE.md`** だけなので、プロジェクトの `CLAUDE.md` はそのまま Claude Code が読み込みます。両方とも有効です。

### Q. global.md と repos/*.md が両方ある場合、どちらが優先される?

A. どちらも CLAUDE.md に注入されて Claude が読みます。内容が矛盾した場合の動作は未定義です。矛盾しないように書いてください。一般には「global.md は一般方針」「repos/*.md は例外やプロジェクト固有」という切り分けが自然です。

### Q. Claude Code を使わないプロジェクトでも記憶は更新される?

A. `UserPromptSubmit` / `Stop` hook は Claude Code を起動したときだけ発火するので、他のエディタ作業中には何も起きません。

### Q. 記憶ファイルに GitHub token や API key を誤って書いてしまった

A. セッション終了時または `cm sync` 実行時にシークレットスキャナが検出して commit を中止します。記憶ファイルから該当行を削除して再実行してください。

もし既に push してしまった場合は、**即座に該当トークンを revoke** して、git history を書き換え (`git filter-repo` など) してください。この場合の対応は本ツールの責務を超えます。

### Q. 20 リポジトリで使いたい

A. 問題ありません。プロジェクト固有の記憶は `repos/{git-remote-slug}.md` に分離されるので、何個でも並行可能です。global.md は全プロジェクトで共有されます。

### Q. Windows でも動く?

A. **macOS / Linux 前提**です。`install.sh` と shell hook が POSIX シェルを要求します。WSL2 なら動くはずですが検証していません。

### Q. Zsh じゃなく別のシェルでも動く?

A. `install.sh` の PATH 自動追記プロンプトは zsh / bash を認識します。fish / nushell 等を使っている場合は手動で `~/.local/bin` を PATH に追加してください。フック本体は `/bin/bash` で動くので、ログインシェルが何であれ問題ありません。

### Q. fork して自分で改造したい

A. `CLAUDE_MEMORY_SYNC_REPO` 環境変数を設定して install.sh を実行すると、そのリポジトリから clone します。

```bash
CLAUDE_MEMORY_SYNC_REPO=https://github.com/you/claude-memory-sync-fork \
  ./install.sh
```

または開発中なら `~/.claude/skills/memory-sync` を fork リポジトリへのシンボリックリンクにしても OK です。詳しくは [CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

---

## 環境変数

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CLAUDE_MEMORY_DIR` | 記憶リポジトリのパス | `~/.claude-memory` |
| `CLAUDE_MEMORY_AUTO_PUSH` | `1` / `true` でセッション終了時の自動 push を有効化 | (off) |
| `CLAUDE_MEMORY_SKIP_SECRET_SCAN` | `1` / `true` でシークレットスキャナをバイパス | (off) |
| `CLAUDE_MEMORY_SYNC_REPO` | install.sh が skill を clone する元 URL (fork / private mirror 用) | 本リポジトリ |
| `EDITOR` | `cm edit` が使うエディタ | `nano` |

---

## アンインストール

```bash
node ~/.claude/skills/memory-sync/bin/uninstall.js
```

- マーカー付きで登録した `UserPromptSubmit` / `Stop` hook のみを `~/.claude/settings.json` から削除します
- ユーザーが独自に登録した他の hook は触りません
- `~/.claude/CLAUDE.md` の注入ブロックも自動で削除しますが、手書きコンテンツは保持されます
- 記憶リポジトリ (`~/.claude-memory/`) は **削除されません**。不要なら手動で `rm -rf` してください

---

## コントリビューション

バグ報告・機能提案・Pull Request は歓迎です。[CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

変更履歴は [CHANGELOG.md](./CHANGELOG.md) を参照。

---

## License

[MIT](./LICENSE)
