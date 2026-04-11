#!/bin/bash
# claude-memory-sync: cleanup
# ~/.claude/CLAUDE.md から claude-memory-sync の注入ブロックを削除する。
# アンインストール時や手動クリーンアップ時に使用。
#
# 堅牢性の担保:
#   - 複数の begin/end ペアが混ざっていても、全ての begin/end マーカー行を
#     除去しつつ、その間の行も削除する。
#   - 偽 begin / 偽 end による攻撃的な残留 (プロンプトインジェクション持ち込み)
#     を防ぐため、1 ブロック目の end で停止せず、最後の end まで読む。

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
INJECT_BEGIN="<!-- claude-memory-sync:begin -->"
INJECT_END="<!-- claude-memory-sync:end -->"

# 旧バージョン (v0.0.x) の単一マーカーも互換のため剥がす
LEGACY_MARKER="<!-- claude-memory-sync: auto-generated -->"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "$CLAUDE_MD が存在しません"
  exit 0
fi

TMP=$(mktemp "${TMPDIR:-/tmp}/cms-cleanup.XXXXXX")
TMP2=$(mktemp "${TMPDIR:-/tmp}/cms-cleanup2.XXXXXX")
# EXIT trap で両ファイルを確実に削除 (途中終了・シグナル受信を含む)
trap 'rm -f "$TMP" "$TMP2"' EXIT

# Pass 1: 旧マーカー以降を全削除、新マーカーは全ての begin/end マーカー行と
# その間のテキスト (最初の begin から最後の end まで) を削除する。
#
# 具体的なアルゴリズム:
#   - 旧 legacy マーカーに出会ったら以降全行破棄
#   - 最初に begin が出現したら inside=1
#   - inside=1 の間は全行破棄
#   - inside=1 中に begin が再出現しても無視 (そのまま inside 維持)
#   - end が出現したら inside=0
#   - inside=0 に戻った後、再び begin が出現したらまた inside=1
awk -v begin="$INJECT_BEGIN" -v end="$INJECT_END" -v legacy="$LEGACY_MARKER" '
  legacy_found { next }
  $0 == legacy { legacy_found = 1; next }
  $0 == begin  { inside = 1; next }
  inside && $0 == end { inside = 0; next }
  inside { next }
  { print }
' "$CLAUDE_MD" > "$TMP"

# 末尾に連続する空行を 1 つに圧縮 + 最終空行を 1 つに揃える
awk '
  /^[[:space:]]*$/ { blank++; next }
  { while (blank-- > 0) print ""; blank = 0; print }
  END { if (blank > 0) print "" }
' "$TMP" > "$TMP2"

# atomic rename
mv "$TMP2" "$CLAUDE_MD"

echo "✓ 注入ブロックを削除しました"
