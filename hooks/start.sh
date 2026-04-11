#!/bin/bash
# claude-memory-sync: start hook
# セッション開始時に記憶を ~/.claude/CLAUDE.md（グローバル）へ注入する
# プロジェクト内の CLAUDE.md には一切書き込まない

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO=$(basename "$(pwd)")
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
INJECT_MARKER="<!-- claude-memory-sync: auto-generated -->"

# 記憶リポジトリが存在しない場合はスキップ
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# 最新の記憶を取得（リモートがある場合のみ）
if [ -d "$MEMORY_DIR/.git" ]; then
  if git -C "$MEMORY_DIR" remote | grep -q .; then
    git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true
  fi
fi

GLOBAL="$MEMORY_DIR/global.md"
PROJECT="$MEMORY_DIR/repos/${REPO}.md"

# 注入する内容がなければ既存の注入ブロックだけ削除してスキップ
if [ ! -f "$GLOBAL" ] && [ ! -f "$PROJECT" ]; then
  if [ -f "$CLAUDE_MD" ]; then
    sed -i.bak "/$INJECT_MARKER/,\$d" "$CLAUDE_MD" 2>/dev/null || true
    rm -f "${CLAUDE_MD}.bak"
  fi
  exit 0
fi

# ~/.claude/ ディレクトリが存在しない場合は作成
mkdir -p "$CLAUDE_DIR"

# 注入ブロックを生成
TMPFILE=$(mktemp)
{
  echo "$INJECT_MARKER"
  echo "<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->"
  echo ""

  if [ -f "$GLOBAL" ]; then
    echo "## グローバル設計方針"
    echo ""
    cat "$GLOBAL"
    echo ""
  fi

  if [ -f "$PROJECT" ]; then
    echo "## プロジェクト固有の記憶（${REPO}）"
    echo ""
    cat "$PROJECT"
    echo ""
  fi
} > "$TMPFILE"

# 既存の注入ブロックを削除してから末尾に追記
if [ -f "$CLAUDE_MD" ]; then
  sed -i.bak "/$INJECT_MARKER/,\$d" "$CLAUDE_MD" 2>/dev/null || true
  rm -f "${CLAUDE_MD}.bak"
  # 末尾の空行を整える
  sed -i.bak -e 's/[[:space:]]*$//' "$CLAUDE_MD" 2>/dev/null || true
  rm -f "${CLAUDE_MD}.bak"
  echo "" >> "$CLAUDE_MD"
fi

cat "$TMPFILE" >> "$CLAUDE_MD"
rm -f "$TMPFILE"
