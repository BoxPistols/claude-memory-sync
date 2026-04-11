#!/bin/bash
# claude-memory-sync: cleanup
# ~/.claude/CLAUDE.md から claude-memory-sync の注入ブロックを削除する。
# アンインストール時や手動クリーンアップ時に使用。

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
INJECT_BEGIN="<!-- claude-memory-sync:begin -->"
INJECT_END="<!-- claude-memory-sync:end -->"

# 旧バージョン (v0.0.x) のマーカーも互換のため剥がす
LEGACY_MARKER="<!-- claude-memory-sync: auto-generated -->"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "~/.claude/CLAUDE.md が存在しません"
  exit 0
fi

# begin/end マーカー間を削除 (新方式) + 旧方式の legacy マーカー以降を削除
awk -v begin="$INJECT_BEGIN" -v end="$INJECT_END" -v legacy="$LEGACY_MARKER" '
  # Legacy: legacy マーカー以降の行を全て削除 (行末までしか残さない)
  legacy_found { next }
  $0 == legacy { legacy_found = 1; next }
  # 新方式: begin/end ブロックを削除
  $0 == begin { skipping = 1; next }
  skipping && $0 == end { skipping = 0; next }
  !skipping { print }
' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"

# 末尾に連続する空行を 1 つに圧縮 (削除で余計な空行が残ることがあるため)
awk '
  /^[[:space:]]*$/ { blank++; next }
  { while (blank-- > 0) print ""; blank = 0; print }
  END { if (blank > 0) print "" }
' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"

echo "✓ 注入ブロックを削除しました"
