# claude-memory-sync

Claude Code にセッション間の記憶を持たせる自作メモリ層。**外部サービス不要・コストゼロ・完全自己管理。**

`~/.claude-memory/` というプライベート Git リポジトリにグローバル方針 (`global.md`) とプロジェクト固有の記憶 (`repos/*.md`) を保存し、Claude Code の `UserPromptSubmit` hook 経由で `~/.claude/CLAUDE.md` に自動注入する。push は手動 (`cm`) が推奨で、機密情報漏洩を防ぐため自動 push はデフォルト OFF。

## 特徴

- **プロジェクトを汚さない** — 注入先は `~/.claude/CLAUDE.md` (グローバル) のみ。各リポジトリ内の `CLAUDE.md` には一切書かない
- **外部サービス不要** — 記憶はあなた自身のプライベート Git リポジトリ上に置く。LLM プロバイダにもどこにもソースコードは送信されない
- **複数 PC 対応** — `cm` コマンドで git pull / push するだけ
- **複数リポジトリ対応** — グローバル方針 + プロジェクト固有の記憶を自動で合成
- **プロジェクト衝突回避** — git remote URL ベースの slug で識別するので、同名 basename の別リポジトリが混ざらない
- **シークレットスキャナ内蔵** — commit 前に API キー / トークン / 秘密鍵の典型パターンを検出して誤漏洩を防ぐ
- **自動 push はデフォルト OFF** — 意図しないリモート反映を防止。明示的に opt-in (`CLAUDE_MEMORY_AUTO_PUSH=1`) できる
- **クリーンなアンインストール** — マーカー付きで登録した hook だけを削除。ユーザーの他の hook や `CLAUDE.md` の手書きコンテンツは触らない

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
```

インストーラがやること:

1. `~/.claude/skills/memory-sync/` に本リポジトリをクローン
2. `~/.claude-memory/` (記憶リポジトリ) を作成。対話で private GitHub repo URL を入力できる (空 Enter でローカルのみ)
3. `~/.claude/settings.json` に `UserPromptSubmit` / `Stop` hook をマーカー付きで登録
4. `~/.local/bin/cm` に `cm` コマンドをシンボリックリンク
5. (対話モードなら) `~/.local/bin` が PATH になければ `~/.zshrc` または `~/.bashrc` に追記するか確認

### 前提

- [Claude Code](https://claude.ai/code) がインストール済み
- Git + Node.js v18 以上

## 使い方

### 日常の流れ

```bash
claude   # いつも通り起動するだけ。記憶が自動注入される
```

作業中または終わりに Claude へ一言:

```
今日の知見を記憶して
```

Claude が `~/.claude-memory/repos/{project-key}.md` に追記する。セッション終了時に **commit は自動、push は明示 opt-in**。

### `cm` コマンド

```bash
cm              # pull --rebase → secret scan → commit → push
cm status       # ファイル一覧 + ahead/behind + 未 commit 変更 + 最終 commit
cm log          # 最近の commit 10 件
cm edit         # global.md を $EDITOR で開く
cm clean        # ~/.claude/CLAUDE.md から注入ブロックを削除
```

## 記憶ファイルの構造

```
~/.claude-memory/
├── global.md                              # 全 PJ 共通の設計方針 (手動編集)
└── repos/
    ├── github.com-you-project-a.md        # Claude が自動追記する PJ 固有の記憶
    ├── github.com-you-project-b.md
    └── gitlab.com-you-internal-tool.md
```

ファイル名は **git remote origin URL を slug 化**したもの:

- `github.com-owner-repo` (HTTPS / SSH どちらでも同じ slug)
- `git remote` が未設定なら git worktree root の basename
- git リポジトリでもないディレクトリでは PWD の basename

同じ `project-a` という basename でも remote が違えば別ファイルとして管理される。

## 注入の仕組み

`~/.claude/CLAUDE.md` (グローバル) にのみ書き込む。プロジェクト内の `CLAUDE.md` には一切触らない。

```
~/.claude/CLAUDE.md
  (手書きの内容があればそのまま残る)
  <!-- claude-memory-sync:begin -->
    ## グローバル設計方針
    (global.md の内容)
    ## プロジェクト固有の記憶 (github.com-you-project-a)
    (repos/github.com-you-project-a.md の内容)
  <!-- claude-memory-sync:end -->
```

`begin` / `end` マーカーで sandwich されているので、セッション開始ごとにブロック内だけが再生成される。ユーザーの手書きコンテンツは上書きされない。

## セッション終了時の動作

`Stop` hook は以下の順で動く:

1. 記憶リポジトリに変更があるかチェック (なければ終了)
2. **シークレットスキャナ** で変更内容を検査。`sk-*` / `ghp_*` / AWS / JWT / PEM 等の典型パターンにマッチしたら **commit を中止**
3. 問題がなければ `git commit`
4. `CLAUDE_MEMORY_AUTO_PUSH=1` が設定されていれば自動 push (デフォルト: **off**)

push がデフォルト off なのは、Claude が誤って API キーや機密情報を記憶ファイルに書き込んだとき、意図せずリモートへ漏洩することを避けるため。日常的な push は `cm` を明示的に実行することを推奨する。

## セキュリティ

- 記憶ファイルには **方針・パターン・禁止事項のみ** を書く。コードは書かない
- シークレットスキャナが commit 前に API キー / トークン / 秘密鍵の典型パターンを検出 (`sk-*`, `ghp_*`, `AKIA*`, `eyJ*` JWT, PEM private key 等)
- 一時的バイパスが必要な場合は `CLAUDE_MEMORY_SKIP_SECRET_SCAN=1` を明示的に設定
- 記憶リポジトリは **プライベート** Git リポジトリに置くことを強く推奨
- 本スキャナは best-effort。真剣なシークレット検出には [trufflehog](https://github.com/trufflesecurity/trufflehog) / [gitleaks](https://github.com/gitleaks/gitleaks) 等を併用のこと

## 複数 PC 運用

```bash
# 別 PC での初回セットアップ (同じコマンド)
curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash
# 既存の記憶リポジトリ URL を入力するだけ
```

`cm` で同期。`cm status` で ahead/behind を確認できる。

## 環境変数

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CLAUDE_MEMORY_DIR` | 記憶リポジトリのパス | `~/.claude-memory` |
| `CLAUDE_MEMORY_AUTO_PUSH` | `1` / `true` でセッション終了時の自動 push を有効化 | (off) |
| `CLAUDE_MEMORY_SKIP_SECRET_SCAN` | `1` / `true` でシークレットスキャナをバイパス | (off) |
| `CLAUDE_MEMORY_SYNC_REPO` | install.sh が skill を clone する元 URL (fork / private mirror 用) | 本リポジトリ |

## アンインストール

```bash
node ~/.claude/skills/memory-sync/bin/uninstall.js
```

マーカー付きで登録した `UserPromptSubmit` / `Stop` hook のみを `~/.claude/settings.json` から削除する。ユーザーが独自に登録した他の hook や、`~/.claude/CLAUDE.md` の手書きコンテンツは触らない。記憶リポジトリ (`~/.claude-memory`) は削除されないので、不要であれば手動で削除すること。

## コントリビューション

[CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

## License

[MIT](./LICENSE)
