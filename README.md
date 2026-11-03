# claude-memory-sync

個人の開発方針と、プロジェクトごとに溜めた記憶をプライベート Git リポジトリで複数 PC に同期し、Claude Code のセッション開始時に流し込む hook セット。外部サービスは使いません。

[![CI](https://github.com/BoxPistols/claude-memory-sync/actions/workflows/ci.yml/badge.svg)](https://github.com/BoxPistols/claude-memory-sync/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

## 実行例

記憶リポジトリ (`~/.claude-memory`) に `global.md` と `repos/github.com-you-my-app.md` がある状態で、`my-app` で Claude Code を起動したときに `SessionStart` hook (`hooks/start.sh`) が書き出す内容です (一時 `HOME` で実際に実行した出力)。

```console
$ cat ~/.claude/CLAUDE.md
# 手書きの内容 (そのまま残る)
<!-- claude-memory-sync:begin -->
<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->

## グローバル設計方針

- パッケージ管理は pnpm
- MUI の sx は spacing 単位で書く (px 禁止)

<!-- claude-memory-sync:end -->

$ cat CLAUDE.local.md
<!-- claude-memory-sync:begin -->
<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->

## プロジェクト固有の記憶 (github.com-you-my-app)

- API クライアントは src/lib/api.ts に集約する

<!-- claude-memory-sync:end -->

$ git status --short     # CLAUDE.local.md は .git/info/exclude に入るので出てこない
$
```

## 見どころ

- **注入先をセッション単位で分ける**: 全プロジェクト共通の `global.md` は `~/.claude/CLAUDE.md` へ、プロジェクト固有の `repos/<key>.md` は `<project-root>/CLAUDE.local.md` へ書く。複数リポジトリで同時に起動しても記憶が混ざらない — [`hooks/start.sh`](./hooks/start.sh)
- **commit 前のシークレット検査と commit 対象の絞り込み**: API キー・秘密鍵のパターンを検出したら commit を止め、`.md` と追跡済みファイル以外は stage しない — [`hooks/scan-secrets.sh`](./hooks/scan-secrets.sh) / [`hooks/stop.sh`](./hooks/stop.sh)
- **既存設定を壊さない hook 登録**: マーカー付きで `~/.claude/settings.json` に登録し、再実行しても二重にならず、アンインストールでは自分の hook だけを外す。挙動は CI の smoke test で確認 — [`bin/setup.js`](./bin/setup.js) / [`tests/smoke.sh`](./tests/smoke.sh)

---

## もくじ

- [何を解決するか (before / after)](#何を解決するか-before--after)
- [アーキテクチャ](#アーキテクチャ)
- [Getting Started (5 分)](#getting-started-5-分)
- [日常の使い方](#日常の使い方)
- [記憶ファイルの書き方](#記憶ファイルの書き方)
- [注入の仕組み](#注入の仕組み)
- [複数 PC 運用](#複数-pc-運用)
- [セキュリティ](#セキュリティ)
- [既知のトレードオフ](#既知のトレードオフ)
- [環境変数](#環境変数)
- [アンインストール](#アンインストール)
- トラブルシューティング / FAQ: [docs/troubleshooting.md](./docs/troubleshooting.md) / [docs/faq.md](./docs/faq.md)

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
```

### After (claude-memory-sync を入れた後)

```
# 最初に 1 度だけ書く:
# ~/.claude-memory/global.md
# ## MUI
# - sx の padding/margin は数値のみ (px 禁止、spacing 単位で)

あなた: 「このコンポーネントに sx で padding 追加して」
Claude: 「sx={{ padding: 2 }} で追加しました」
```

記憶はセッション開始時に `CLAUDE.md` / `CLAUDE.local.md` へ書き出され、Claude Code がそれを読み込みます。反映のタイミングは [注入の仕組み](#注入の仕組み) を参照してください。

---

## アーキテクチャ

```
  ~/.claude-memory/  (プライベート Git リポジトリ)
  ├── global.md                       全プロジェクト共通の方針 (手で書く)
  ├── repos/github.com-you-my-app.md  プロジェクト固有の記憶 (Claude が追記)
  └── rules/*.md                      パス指定ルール (任意)
          │
          │ SessionStart hook (hooks/start.sh)
          │   1. git pull --ff-only (既定 5 秒で打ち切り)
          │   2. cwd の git remote URL からプロジェクトキーを決める
          ▼
  ~/.claude/CLAUDE.md          ← global.md を begin/end マーカーの間に注入
  <project-root>/CLAUDE.local.md ← repos/<key>.md を注入 (.git/info/exclude に追記)
  ~/.claude/rules/             ← rules/*.md をコピー
          │
          ▼
  Claude Code が読み込む

  Stop hook (非同期) / SessionEnd hook (hooks/stop.sh)
    シークレット検査 → commit → (CLAUDE_MEMORY_AUTO_PUSH=1 のときだけ) push
```

### 設計上の決めごと

- **追跡対象のファイルを書き換えない**: 書き込むのは `~/.claude/CLAUDE.md` (グローバル) と、プロジェクト直下の `CLAUDE.local.md` だけ。`CLAUDE.local.md` は `.git/info/exclude` に追記して git の管理外にするので、リポジトリの `CLAUDE.md` や `.gitignore` は変わらない
- **記憶は Git 管理**: プライベート Git リポジトリに置くので、バックアップ・履歴・複数 PC 同期が全て Git の仕組みで完結
- **自動 push はデフォルト OFF**: Claude が誤って API キー等を書き込んだ場合にリモートへ漏洩しないよう、push は `cm` コマンドで明示的に実行することを推奨
- **シークレットスキャナ内蔵**: commit 前に `sk-*`, `ghp_*`, `AWS AKIA*`, JWT, PEM 等の典型パターンを検出

### 特徴

- **外部サービス不要** — 全ての記憶はあなた自身の Git リポジトリに
- **複数 PC 対応** — `cm` コマンドで git pull / push するだけ
- **複数リポジトリ対応** — git remote URL ベースの slug で記憶を自動で切り替える
- **opt-in な自動 push** — 意図しないリモート反映を防止
- **クリーンなアンインストール** — 自分が登録した hook と注入ブロックだけを削除

(実装の変遷は [CHANGELOG.md](./CHANGELOG.md) を参照)

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

起動すると `~/.claude/CLAUDE.md` に Step 3 で書いた方針が自動注入されます。`CLAUDE.md` は hook より先に読み込まれるため、内容が効くのは次に起動したセッションからです (`setup.js --global-context` を使うと同じセッションから効きます。詳細は [注入の仕組み](#注入の仕組み))。もう一度 `claude` を起動し、記憶が効いているか確認してください。

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
| `cm clean` | `~/.claude/CLAUDE.md` と `./CLAUDE.local.md` から注入ブロックを削除 (再インストール時など) |
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

書き込み先は 2 箇所です。リポジトリで追跡されている `CLAUDE.md` には触りません。

```
~/.claude/CLAUDE.md                     (全プロジェクト共通)
  (あなたの手書きコンテンツ — そのまま残る)
  <!-- claude-memory-sync:begin -->
    ## グローバル設計方針
    (global.md の内容)
  <!-- claude-memory-sync:end -->

<project-root>/CLAUDE.local.md          (そのプロジェクトだけ)
  <!-- claude-memory-sync:begin -->
    ## プロジェクト固有の記憶 (github.com-you-project-a)
    (repos/github.com-you-project-a.md の内容)
  <!-- claude-memory-sync:end -->
```

`begin` / `end` マーカーで挟んだブロックの中だけを再生成するので、手書きの内容は上書きされません。内容が前回と同じなら書き込み自体を省きます。`CLAUDE.local.md` は git に追跡されていなければ `.git/info/exclude` に追記してから書きます。プロジェクトに記憶が無くなった場合は前回のブロックを削除します。

### セッション終了時の動作

`Stop` hook（応答の終わり、非同期）と`SessionEnd` hook（セッション終了時）は以下の順で動きます:

1. 記憶リポジトリに変更があれば、**シークレットスキャナ**で変更内容を検査。API キー / 秘密鍵の典型パターンにマッチしたら commit を中止
2. 問題がなければ `git commit`。対象は`.md`ファイルと、すでに追跡しているファイルの変更（`git add -u`）。スクリプトなど`.md`以外を同期したいときは、記憶リポジトリの`.gitignore`で許可して一度だけ手で`git add`する。以後の変更は自動でcommitされる
3. `CLAUDE_MEMORY_AUTO_PUSH=1` が設定されていれば自動 push (デフォルト: **off**)。`Stop`では前回のpushから`CLAUDE_MEMORY_PUSH_INTERVAL`秒（既定600）経っているときだけ、`SessionEnd`では常にpushする。他のマシンが先にpushしていたら1回だけrebaseして再試行し、競合したらrebaseを戻してログに残す

`Stop`でもpushするのは、ターミナルを閉じたときに`SessionEnd`が最後まで走る保証がないためです。記憶の取得（pull）と`CLAUDE.md`の合成は`SessionStart`で1回だけ行います。`CLAUDE.md`はセッション開始時と`/compact`後にしか読まれないため、プロンプトごとに合成しても効果がありません。

`CLAUDE.md`は`SessionStart` hookより先に読み込まれるため、合成した内容が効くのは次のセッションからです（`claude -p`で実測）。`--global-context`を付けると、global.mdをhookの出力として渡すので、pull直後の内容がそのセッションで効きます。hookの出力には公式の上限（10,000文字）があるため、プロジェクト固有の記憶は`CLAUDE.local.md`のままです。記憶リポジトリの`rules/*.md`は`~/.claude/rules/`へコピーされ、`paths`を指定したルールは該当ファイルを読んだときだけ読み込まれます。

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

- **セッション開始時**: `git pull --ff-only` で最新を自動取得 (失敗は `~/.claude/logs/claude-memory-sync.log` に記録)
- **セッション終了時**: `git commit` (push はデフォルト off)
- **手動**: `cm` で pull → commit → push を明示実行

### 競合した場合

異なる PC で同じファイルを編集して競合したら、`cm` が `pull --rebase` で取り込みを試みます。自動解決できない場合は明示的なエラーで止まり、手動で解決するよう促します (以前の `pull --ff-only` + 黙殺とは違います)。

---

## セキュリティ

### 信頼モデル (必読)

本ツールは以下の前提で動きます:

1. **memory リポジトリに書き込める人 = あなたの Claude Code の振る舞いを実質的に操作できる人**です。memory repo の内容は `~/.claude/CLAUDE.md` と各プロジェクトの `CLAUDE.local.md` に注入され、Claude Code のセッションのプロンプトになります。プロンプトインジェクションで情報漏洩・不正指示を仕込むことが可能です
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
node bin/setup.js --auto-push           # 自動pushをhookのコマンドに埋め込む（マシンごとに1回）
```

後者は危険 (push 前に人間が確認できない) なので、**信頼できる環境でのみ** 使ってください。

---

## 既知のトレードオフ

### セッション開始時の pull は同期的に待つ

`SessionStart` hook は記憶を最新にしてから注入するため、`git pull --ff-only` の完了を待ちます。オフラインやリモートの応答が遅いときにセッション開始が止まらないよう、`CLAUDE_MEMORY_PULL_TIMEOUT` 秒 (既定 5) で pull を打ち切り、手元の記憶で続行します (失敗は `~/.claude/logs/claude-memory-sync.log` に記録)。待ち時間を減らしたい場合はこの値を小さくしてください。

### 旧版の `UserPromptSubmit` hook が残っている場合

以前の版は `UserPromptSubmit` (プロンプト送信ごと) に `start.sh` を登録していたため、プロンプトのたびに `git pull` が走っていました。現在の版は `SessionStart` でのみ実行します。旧版から更新したマシンでは `~/.claude/settings.json` に古い登録が残っていることがあるので、`node ~/.claude/skills/memory-sync/bin/setup.js` を再実行してください。旧登録を外してから現在の hook を登録し直します。

```bash
# 残っているか確認
grep -n UserPromptSubmit ~/.claude/settings.json
```

---

## 環境変数

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CLAUDE_MEMORY_DIR` | 記憶リポジトリのパス | `~/.claude-memory` |
| `CLAUDE_MEMORY_AUTO_PUSH` | `1` / `true` でセッション終了時の自動 push を有効化 | (off) |
| `CLAUDE_MEMORY_PUSH_INTERVAL` | `Stop`でpushする最短間隔（秒） | `600` |
| `CLAUDE_MEMORY_PULL_TIMEOUT` | `SessionStart`のpullを打ち切るまでの秒数 | `5` |
| `CLAUDE_MEMORY_GLOBAL_MODE` | `context`のとき、global.mdを`CLAUDE.md`ではなく`SessionStart`の出力で渡す（`setup.js --global-context`で設定）。9,500文字を超えると`CLAUDE.md`へ戻す | (未設定) |
| `CLAUDE_MEMORY_SKIP_SECRET_SCAN` | `1` / `true` でシークレットスキャナをバイパス | (off) |
| `CLAUDE_MEMORY_SYNC_REPO` | install.sh が skill を clone する元 URL (fork / private mirror 用) | 本リポジトリ |
| `EDITOR` | `cm edit` が使うエディタ | `nano` |

---

## アンインストール

```bash
node ~/.claude/skills/memory-sync/bin/uninstall.js
```

- マーカー付きで登録した `SessionStart` / `Stop` / `SessionEnd` hook（旧版の`UserPromptSubmit`を含む）のみを `~/.claude/settings.json` から削除します
- ユーザーが独自に登録した他の hook は触りません
- `~/.claude/CLAUDE.md` の注入ブロックも自動で削除しますが、手書きコンテンツは保持されます。各プロジェクトの `CLAUDE.local.md` は対象外なので、必要ならプロジェクト直下で `cm clean` を実行するか削除してください
- 記憶リポジトリ (`~/.claude-memory/`) は **削除されません**。不要なら手動で `rm -rf` してください

---

## コントリビューション

バグ報告・機能提案・Pull Request は歓迎です。[CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

変更履歴は [CHANGELOG.md](./CHANGELOG.md) を参照。

---

## License

[MIT](./LICENSE)
