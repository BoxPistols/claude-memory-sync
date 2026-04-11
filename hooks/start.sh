#!/bin/bash
# claude-memory-sync: start hook
# セッション開始時に記憶を ~/.claude/CLAUDE.md (グローバル) へ注入する。
# プロジェクト内の CLAUDE.md には一切書き込まない。
#
# 環境変数:
#   CLAUDE_MEMORY_DIR   記憶リポジトリのパス (デフォルト: ~/.claude-memory)

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
INJECT_BEGIN="<!-- claude-memory-sync:begin -->"
INJECT_END="<!-- claude-memory-sync:end -->"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 記憶リポジトリが存在しない場合はスキップ
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# 最新の記憶を取得 (リモートがある場合のみ) — 失敗はログに残して続行
if [ -d "$MEMORY_DIR/.git" ]; then
  if git -C "$MEMORY_DIR" remote | grep -q .; then
    if ! git -C "$MEMORY_DIR" pull --quiet --ff-only 2>/tmp/claude-memory-sync-pull.err; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] start.sh: pull --ff-only failed" \
        >> /tmp/claude-memory-sync.log
      cat /tmp/claude-memory-sync-pull.err >> /tmp/claude-memory-sync.log 2>/dev/null || true
      rm -f /tmp/claude-memory-sync-pull.err
    fi
  fi
fi

# プロジェクトキーを決定する
# 1. git remote origin URL があればホスト+パスを slug 化 (一番安定)
# 2. なければ git worktree のルートの basename
# 3. どちらも取れなければ現在ディレクトリの basename
project_key() {
  local url
  if url=$(git -C "$PWD" config --get remote.origin.url 2>/dev/null) && [ -n "$url" ]; then
    # git@github.com:owner/repo.git → github.com-owner-repo
    # https://github.com/owner/repo.git → github.com-owner-repo
    printf '%s' "$url" \
      | sed -E 's|^git@([^:]+):|\1/|; s|^https?://||; s|\.git$||; s|/|-|g; s|:|-|g'
    return
  fi
  local root
  if root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
    basename "$root"
    return
  fi
  basename "$PWD"
}

REPO=$(project_key)

# 空白 / スラッシュ / 危険文字を除去しておく (念のため)
REPO=$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9._-' '-')

GLOBAL="$MEMORY_DIR/global.md"
PROJECT="$MEMORY_DIR/repos/${REPO}.md"

# 注入する内容がなければ既存の注入ブロックだけ削除して終了
if [ ! -f "$GLOBAL" ] && [ ! -f "$PROJECT" ]; then
  if [ -f "$CLAUDE_MD" ]; then
    bash "$SKILL_DIR/hooks/cleanup.sh" >/dev/null 2>&1 || true
  fi
  exit 0
fi

mkdir -p "$CLAUDE_DIR"

# 注入ブロックを生成
TMPFILE=$(mktemp)
{
  echo "$INJECT_BEGIN"
  echo "<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->"
  echo ""

  if [ -f "$GLOBAL" ]; then
    echo "## グローバル設計方針"
    echo ""
    cat "$GLOBAL"
    echo ""
  fi

  if [ -f "$PROJECT" ]; then
    echo "## プロジェクト固有の記憶 (${REPO})"
    echo ""
    cat "$PROJECT"
    echo ""
  fi

  echo "$INJECT_END"
} > "$TMPFILE"

# 既存の注入ブロックを削除 (begin/end マーカー間) してから挿入
if [ -f "$CLAUDE_MD" ]; then
  awk -v begin="$INJECT_BEGIN" -v end="$INJECT_END" '
    $0 == begin { skipping = 1; next }
    skipping && $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
  mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
  # 末尾に必ず空行を 1 つ置いてから注入
  if [ -s "$CLAUDE_MD" ]; then
    tail -c 1 "$CLAUDE_MD" | read -r _ || echo "" >> "$CLAUDE_MD"
  fi
fi

cat "$TMPFILE" >> "$CLAUDE_MD"
rm -f "$TMPFILE"
