#!/bin/bash
# claude-memory-sync: start hook
# Claude Code セッション開始時に記憶を CLAUDE.md へ注入する

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
REPO=$(basename "$(pwd)")
INJECT_MARKER="<!-- claude-memory-sync: auto-generated -->"

# 記憶リポジトリが存在しない場合はスキップ
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# 最新の記憶を取得
if [ -d "$MEMORY_DIR/.git" ]; then
  git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/dev/null || true
fi

GLOBAL="$MEMORY_DIR/global.md"
PROJECT="$MEMORY_DIR/repos/${REPO}.md"

# 注入する内容がなければスキップ
if [ ! -f "$GLOBAL" ] && [ ! -f "$PROJECT" ]; then
  exit 0
fi

# 一時ファイルで生成
TMPFILE=$(mktemp)

{
  echo "$INJECT_MARKER"
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

# 既存の CLAUDE.md に追記 or 作成
CLAUDE_MD="$(pwd)/CLAUDE.md"

if [ -f "$CLAUDE_MD" ]; then
  # 既存の注入ブロックを削除してから追記
  # マーカー以降を削除
  sed -i.bak "/$INJECT_MARKER/,\$d" "$CLAUDE_MD" 2>/dev/null || true
  rm -f "${CLAUDE_MD}.bak"
  cat "$TMPFILE" >> "$CLAUDE_MD"
else
  cat "$TMPFILE" > "$CLAUDE_MD"
fi

rm -f "$TMPFILE"
