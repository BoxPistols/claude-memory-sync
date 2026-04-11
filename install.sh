#!/bin/bash
# claude-memory-sync インストーラ
# 使い方: curl -fsSL https://raw.githubusercontent.com/BoxPistols/claude-memory-sync/main/install.sh | bash

set -euo pipefail

SKILL_DIR="${HOME}/.claude/skills/memory-sync"
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO_URL="https://github.com/BoxPistols/claude-memory-sync"  # ← 公開後に自分のURLに変更

echo ""
echo "🧠 claude-memory-sync セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 依存チェック ────────────────────────────────────────────────
echo ""
echo "▶ 依存関係を確認中..."

for cmd in git node; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "  ❌ $cmd が見つかりません。インストールしてください"
    exit 1
  fi
done

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo "  ❌ Node.js v18 以上が必要です（現在: $(node --version)）"
  exit 1
fi

echo "  ✓ git: $(git --version | awk '{print $3}')"
echo "  ✓ node: $(node --version)"

# ── Skill をインストール ────────────────────────────────────────
echo ""
echo "▶ Skill をインストール中..."

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
chmod +x "$SKILL_DIR/bin/cm"

# cm を PATH に追加
LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "$LOCAL_BIN"
ln -sf "$SKILL_DIR/bin/cm" "$LOCAL_BIN/cm"

# PATH に ~/.local/bin が含まれているか確認
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo ""
  echo "  ⚠️  ~/.local/bin を PATH に追加してください："
  echo "     echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
fi

echo "  ✓ Skill をインストールしました: $SKILL_DIR"

# ── 記憶リポジトリのセットアップ ───────────────────────────────
echo ""
echo "▶ 記憶リポジトリのセットアップ..."

if [ -d "$MEMORY_DIR/.git" ]; then
  echo "  既存の記憶リポジトリを使用します: $MEMORY_DIR"
  if git -C "$MEMORY_DIR" remote | grep -q .; then
    git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true
    echo "  ✓ 最新の記憶を取得しました"
  fi
else
  echo ""
  echo "  GitHubにプライベートリポジトリを作成してURLを入力してください"
  echo "  例: git@github.com:YOUR-USERNAME/claude-memory-private.git"
  echo "  （空 Enter でローカルのみ / Git同期なし）"
  echo ""

  # curl | bash 経由の場合は /dev/tty から読む
  if [ -t 0 ]; then
    read -r -p "  Git URL: " MEMORY_REPO_URL
  else
    read -r -p "  Git URL: " MEMORY_REPO_URL < /dev/tty
  fi

  if [ -n "$MEMORY_REPO_URL" ]; then
    git clone --quiet "$MEMORY_REPO_URL" "$MEMORY_DIR"
    echo "  ✓ 記憶リポジトリをクローンしました"
  else
    mkdir -p "$MEMORY_DIR/repos"
    git -C "$MEMORY_DIR" init --quiet
    echo "  ✓ ローカル記憶リポジトリを作成しました"
  fi

  # global.md のテンプレートを配置（なければ）
  if [ ! -f "$MEMORY_DIR/global.md" ]; then
    cp "$SKILL_DIR/template/global.md" "$MEMORY_DIR/global.md"
    echo "  ✓ global.md を初期化しました（編集してください）"
  fi

  mkdir -p "$MEMORY_DIR/repos"
fi

# ── hook を settings.json に登録 ────────────────────────────────
echo ""
echo "▶ Claude Code hook を登録中..."
node "$SKILL_DIR/bin/setup.js"

# ── グローバル .gitignore の確認 ───────────────────────────────
echo ""
echo "▶ グローバル .gitignore を確認中..."

GLOBAL_GITIGNORE=$(git config --global core.excludesfile 2>/dev/null || echo "")

if [ -z "$GLOBAL_GITIGNORE" ]; then
  GLOBAL_GITIGNORE="$HOME/.gitignore_global"
  git config --global core.excludesfile "$GLOBAL_GITIGNORE"
fi

# .letta/ が含まれていなければ追加（念のため）
touch "$GLOBAL_GITIGNORE"
if ! grep -q "^\.letta/$" "$GLOBAL_GITIGNORE" 2>/dev/null; then
  echo ".letta/" >> "$GLOBAL_GITIGNORE"
  echo "  ✓ .letta/ をグローバル .gitignore に追加しました"
else
  echo "  ✓ グローバル .gitignore は設定済みです"
fi

# ── 完了 ───────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップ完了"
echo ""
echo "使い方:"
echo "  claude            次回起動から記憶が自動注入されます"
echo "  cm                記憶を手動でGit同期"
echo "  cm status         記憶の状態を確認"
echo "  cm edit           global.md をエディタで編集"
echo "  cm clean          ~/.claude/CLAUDE.md の注入ブロックを削除"
echo ""
echo "記憶ファイル:"
echo "  $MEMORY_DIR/global.md        全PJ共通の設計方針"
echo "  $MEMORY_DIR/repos/*.md       PJごとの記憶"
echo ""
echo "  Claudeに「今日の知見を記憶して」と言えば自動更新されます"
echo ""
echo "アンインストール:"
echo "  node ~/.claude/skills/memory-sync/bin/uninstall.js"
echo ""
