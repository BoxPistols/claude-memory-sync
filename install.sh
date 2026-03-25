#!/bin/bash
# claude-memory-sync インストーラ
# curl -fsSL https://raw.githubusercontent.com/yourname/claude-memory-sync/main/install.sh | bash

set -euo pipefail

SKILL_DIR="${HOME}/.claude/skills/memory-sync"
MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO_URL="https://github.com/BoxPistols/claude-memory-sync"  # 公開後に変更

echo ""
echo "🧠 claude-memory-sync セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Skill をインストール ──────────────────────────
echo ""
echo "▶ Skill をインストール中..."

mkdir -p "$(dirname "$SKILL_DIR")"

if [ -d "$SKILL_DIR" ]; then
  echo "  既存のインストールを更新します"
  git -C "$SKILL_DIR" pull --quiet
else
  git clone --quiet "$REPO_URL" "$SKILL_DIR"
fi

# 実行権限を付与
chmod +x "$SKILL_DIR/hooks/start.sh"
chmod +x "$SKILL_DIR/hooks/stop.sh"
chmod +x "$SKILL_DIR/bin/cm"

# cm を PATH に通す
BIN_LINK="${HOME}/.local/bin/cm"
mkdir -p "${HOME}/.local/bin"
ln -sf "$SKILL_DIR/bin/cm" "$BIN_LINK"

echo "  ✓ Skill をインストールしました: $SKILL_DIR"

# ── 2. 記憶リポジトリのセットアップ ─────────────────
echo ""
echo "▶ 記憶リポジトリのセットアップ..."

if [ -d "$MEMORY_DIR/.git" ]; then
  echo "  既存の記憶リポジトリを使用します: $MEMORY_DIR"
  git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true
else
  echo ""
  echo "  GitHubにプライベートリポジトリを作成してURLを入力してください"
  echo "  例: git@github.com:yourname/claude-memory-private.git"
  echo ""
  read -r -p "  Git URL（空Enter でローカルのみ）: " MEMORY_REPO_URL

  if [ -n "$MEMORY_REPO_URL" ]; then
    git clone --quiet "$MEMORY_REPO_URL" "$MEMORY_DIR"
    echo "  ✓ 記憶リポジトリをクローンしました"
  else
    mkdir -p "$MEMORY_DIR/repos"
    git -C "$MEMORY_DIR" init --quiet
    echo "  ✓ ローカル記憶リポジトリを作成しました（Git同期なし）"
  fi

  # global.md のテンプレートを配置（なければ）
  if [ ! -f "$MEMORY_DIR/global.md" ]; then
    cp "$SKILL_DIR/template/global.md" "$MEMORY_DIR/global.md"
    echo "  ✓ global.md を初期化しました"
  fi

  mkdir -p "$MEMORY_DIR/repos"
fi

# ── 3. hook を settings.json に登録 ──────────────────
echo ""
echo "▶ Claude Code hook を登録中..."

node "$SKILL_DIR/bin/setup.js"

# ── 4. 完了 ──────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップ完了"
echo ""
echo "使い方:"
echo "  claude          # 次回起動から記憶が自動注入されます"
echo "  cm              # 記憶を手動でGit同期"
echo ""
echo "記憶の編集:"
echo "  $MEMORY_DIR/global.md      # 全PJ共通の方針"
echo "  $MEMORY_DIR/repos/*.md     # PJごとの記憶"
echo ""
echo "  Claudeに「今日の知見を記憶して」と言えば自動更新されます"
echo ""
