#!/bin/bash
# claude-memory-sync インストーラ
# 使い方: curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash

set -euo pipefail

OFFICIAL_REPO_URL="https://github.com/BoxPistols/claude-memory-sync"
SKILL_DIR="${HOME}/.claude/skills/memory-sync"
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO_URL="${CLAUDE_MEMORY_SYNC_REPO:-$OFFICIAL_REPO_URL}"

echo ""
echo "claude-memory-sync セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 依存チェック ────────────────────────────────────────────────
echo ""
echo "▶ 依存関係を確認中..."

for cmd in git node; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "  [error] $cmd が見つかりません。インストールしてください" >&2
    exit 1
  fi
done

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo "  [error] Node.js v18 以上が必要です (現在: $(node --version))" >&2
  exit 1
fi

echo "  ok git: $(git --version | awk '{print $3}')"
echo "  ok node: $(node --version)"

# ── Skill をインストール ────────────────────────────────────────
echo ""
echo "▶ Skill をインストール中..."
echo "  clone 元: $REPO_URL"

# REPO_URL スキーム検証 (ext:: / file:// 等によるコマンド実行を防ぐ)
case "$REPO_URL" in
  https://*|git@*) ;;
  *)
    echo "  [error] CLAUDE_MEMORY_SYNC_REPO に対応していない URL スキームが設定されています" >&2
    echo "          https:// または git@ で始まる URL のみ使用できます" >&2
    exit 1
    ;;
esac

# 公式以外のリポジトリはデフォルトで拒否する
# Claude Code の hook として毎セッション自動実行されるため、
# 任意リポジトリのコードを無審査でインストールするリスクを防ぐ。
# 正当な理由がある場合 (fork / private mirror) は CLAUDE_MEMORY_ALLOW_CUSTOM_REPO=1 を設定。
if [ "$REPO_URL" != "$OFFICIAL_REPO_URL" ]; then
  case "${CLAUDE_MEMORY_ALLOW_CUSTOM_REPO:-}" in
    1|true|TRUE|yes|YES) ;;
    *)
      echo "" >&2
      echo "  [error] 公式以外のリポジトリからのインストールはデフォルトで無効です。" >&2
      echo "          REPO_URL: $REPO_URL" >&2
      echo "" >&2
      echo "          自分の fork や private mirror を使う場合は:" >&2
      echo "          CLAUDE_MEMORY_ALLOW_CUSTOM_REPO=1 bash install.sh" >&2
      echo "" >&2
      exit 1
      ;;
  esac
  echo "  (警告: 公式以外のリポジトリを使用しています — 内容を事前に確認してください)"
fi

mkdir -p "$(dirname "$SKILL_DIR")"

if [ -d "$SKILL_DIR/.git" ]; then
  echo "  既存のインストールを更新します"
  git -C "$SKILL_DIR" pull --quiet
else
  git clone --quiet "$REPO_URL" "$SKILL_DIR"
fi

chmod +x "$SKILL_DIR/hooks/start.sh"
chmod +x "$SKILL_DIR/hooks/stop.sh"
chmod +x "$SKILL_DIR/hooks/cleanup.sh"
chmod +x "$SKILL_DIR/hooks/scan-secrets.sh"
chmod +x "$SKILL_DIR/bin/cm"

# cm を PATH に追加
LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "$LOCAL_BIN"
ln -sf "$SKILL_DIR/bin/cm" "$LOCAL_BIN/cm"

# PATH に ~/.local/bin が含まれているか確認
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo ""
  echo "  ~/.local/bin が PATH に含まれていません。"

  # 該当するシェル RC ファイルを推測
  SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
  case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    *)    SHELL_RC="" ;;
  esac

  # shellcheck disable=SC2016
  # 単一引用符は意図的 — シェル RC ファイルに literal の $HOME/$PATH を書き込みたい
  PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'

  if [ -n "$SHELL_RC" ] && [ -t 0 ]; then
    # 対話的 install の場合のみ自動追記を提示
    printf "  %s に自動的に追記しますか? [y/N]: " "$SHELL_RC"
    read -r ANSWER < /dev/tty || ANSWER="n"
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
      if ! grep -Fq "$PATH_EXPORT" "$SHELL_RC" 2>/dev/null; then
        {
          echo ""
          echo "# claude-memory-sync: cm コマンドへの PATH"
          echo "$PATH_EXPORT"
        } >> "$SHELL_RC"
        echo "  追記しました。新しいシェルで有効になります。"
      else
        echo "  既に追記済みです。"
      fi
    else
      echo "  スキップしました。手動で追加するには:"
      echo "    echo '$PATH_EXPORT' >> $SHELL_RC"
    fi
  else
    echo "  次のコマンドで手動追加してください:"
    [ -n "$SHELL_RC" ] && echo "    echo '$PATH_EXPORT' >> $SHELL_RC" \
                      || echo "    echo '$PATH_EXPORT' >> ~/.zshrc   # zsh の場合"
  fi
fi

echo "  ok Skill をインストールしました: $SKILL_DIR"

# ── 記憶リポジトリのセットアップ ───────────────────────────────
echo ""
echo "▶ 記憶リポジトリのセットアップ..."

if [ -d "$MEMORY_DIR/.git" ]; then
  echo "  既存の記憶リポジトリを使用します: $MEMORY_DIR"
  if git -C "$MEMORY_DIR" remote | grep -q .; then
    git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true
    echo "  ok 最新の記憶を取得しました"
  fi
else
  echo ""
  echo "  GitHub にプライベートリポジトリを作成して URL を入力してください"
  echo "  例: git@github.com:YOUR-USERNAME/claude-memory-private.git"
  echo "  (空 Enter でローカルのみ / Git 同期なし)"
  echo ""

  # curl | bash 経由の場合は /dev/tty から読む
  if [ -t 0 ]; then
    read -r -p "  Git URL: " MEMORY_REPO_URL
  else
    read -r -p "  Git URL: " MEMORY_REPO_URL < /dev/tty
  fi

  if [ -n "$MEMORY_REPO_URL" ]; then
    # URL スキーム検証: https:// または git@ のみ許可 (ext:: / file:// 等を拒否)
    case "$MEMORY_REPO_URL" in
      https://*|git@*)
        ;;
      *)
        echo "  [error] 対応していない URL スキームです。https:// または git@ で始まる URL を入力してください" >&2
        exit 1
        ;;
    esac
    git clone --quiet "$MEMORY_REPO_URL" "$MEMORY_DIR"
    echo "  ok 記憶リポジトリをクローンしました"
  else
    mkdir -p "$MEMORY_DIR/repos"
    git -C "$MEMORY_DIR" init --quiet -b main
    echo "  ok ローカル記憶リポジトリを作成しました (リモートなし)"
  fi

  # global.md のテンプレートを配置 (なければ)
  if [ ! -f "$MEMORY_DIR/global.md" ]; then
    cp "$SKILL_DIR/template/global.md" "$MEMORY_DIR/global.md"
    echo "  ok global.md を初期化しました (cm edit で編集してください)"
  fi

  # .gitignore を配置: .md 以外のファイルが誤って commit されるのを防ぐ
  if [ ! -f "$MEMORY_DIR/.gitignore" ]; then
    cp "$SKILL_DIR/template/.gitignore" "$MEMORY_DIR/.gitignore"
    echo "  ok .gitignore を設置しました (.md のみ追跡)"
  fi

  mkdir -p "$MEMORY_DIR/repos"
fi

# ── hook を settings.json に登録 ────────────────────────────────
echo ""
echo "▶ Claude Code hook を登録中..."
node "$SKILL_DIR/bin/setup.js"

# ── 完了 ───────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "セットアップ完了"
echo ""
echo "使い方:"
echo "  claude            次回起動から記憶が自動注入されます"
echo "  cm                記憶を手動で Git 同期 (pull --rebase + commit + push)"
echo "  cm status         記憶ファイル一覧 + ahead/behind を表示"
echo "  cm log            最近の commit 履歴を表示"
echo "  cm edit           global.md を \$EDITOR で開く"
echo "  cm clean          ~/.claude/CLAUDE.md の注入ブロックを削除"
echo ""
echo "記憶ファイル:"
echo "  $MEMORY_DIR/global.md        全 PJ 共通の設計方針 (手動編集)"
echo "  $MEMORY_DIR/repos/*.md       PJ ごとの記憶 (自動追記)"
echo ""
echo "  Claude に「今日の知見を記憶して」と言えば自動更新されます"
echo ""
echo "環境変数 (optional):"
echo "  CLAUDE_MEMORY_AUTO_PUSH=1       session 終了時の自動 push を有効化"
echo "                                  (デフォルト: off — 意図しない漏洩を防ぐ)"
echo "  CLAUDE_MEMORY_SKIP_SECRET_SCAN=1 シークレットスキャナを一時的にバイパス"
echo ""
echo "アンインストール:"
echo "  node ~/.claude/skills/memory-sync/bin/uninstall.js"
echo ""
