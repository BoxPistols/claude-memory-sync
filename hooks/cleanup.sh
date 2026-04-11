#!/bin/bash
# claude-memory-sync: cleanup
# ~/.claude/CLAUDE.md から注入ブロックを削除する
# アンインストール時や手動クリーンアップ時に使用

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
INJECT_MARKER="<!-- claude-memory-sync: auto-generated -->"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "~/.claude/CLAUDE.md が存在しません"
  exit 0
fi

sed -i.bak "/$INJECT_MARKER/,\$d" "$CLAUDE_MD" 2>/dev/null || true
rm -f "${CLAUDE_MD}.bak"

# 末尾の余分な空行を整える
sed -i.bak -e 's/[[:space:]]*$//' "$CLAUDE_MD" 2>/dev/null || true
rm -f "${CLAUDE_MD}.bak"

echo "✓ 注入ブロックを削除しました"
