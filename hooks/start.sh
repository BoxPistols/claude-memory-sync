#!/bin/bash
# claude-memory-sync: start hook
# セッション開始時に記憶を ~/.claude/CLAUDE.md (グローバル) へ注入する。
# プロジェクト内の CLAUDE.md には一切書き込まない。
#
# 環境変数:
#   CLAUDE_MEMORY_DIR   記憶リポジトリのパス (デフォルト: ~/.claude-memory)
#
# セキュリティ上の注意:
#   - CLAUDE_MEMORY_DIR は $HOME 以下であることを強制 (パス操作防止)。
#   - project_key() の REPO から .. を除去 (パストラバーサル防止)。
#   - sanitize_memory() でマーカーを「含む」行を全除去 (プロンプトインジェクション防止)。
#   - TMPFILE / FINAL_TMP は EXIT trap で確実にクリーンアップ。
#   - CLAUDE.md の更新は cleanup → 合成 → mv でアトミックに行う。
#   - ログ出力は /tmp ではなく ~/.claude/logs/ に置く (symlink 攻撃・情報漏洩対策)。
#   - ログは 1MB 超で自動ローテーション。

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
LOG_DIR="$CLAUDE_DIR/logs"
LOG_FILE="$LOG_DIR/claude-memory-sync.log"
INJECT_BEGIN="<!-- claude-memory-sync:begin -->"
INJECT_END="<!-- claude-memory-sync:end -->"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# MEMORY_DIR が HOME 以下にあることを確認 (任意パス操作の防止)
case "$MEMORY_DIR" in
  "$HOME/"*|"$HOME")
    ;;
  *)
    echo "[claude-memory-sync] CLAUDE_MEMORY_DIR は \$HOME 以下に設定してください: $MEMORY_DIR" >&2
    exit 1
    ;;
esac

# 記憶リポジトリが存在しない場合はスキップ
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# ログディレクトリを確保 (700 で作成)
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR" 2>/dev/null || true

# ログローテーション: 1MB 超えで古いログを退避
rotate_log() {
  local max_bytes=1048576
  if [ -f "$LOG_FILE" ]; then
    local size
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$max_bytes" ]; then
      mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
  fi
}
rotate_log

# 最新の記憶を取得 (リモートがある場合のみ) — 失敗は自ユーザ領域のログに残して続行
if [ -d "$MEMORY_DIR/.git" ]; then
  if git -C "$MEMORY_DIR" remote | grep -q .; then
    ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/cms-pull.XXXXXX")
    if ! git -C "$MEMORY_DIR" pull --quiet --ff-only 2>"$ERR_FILE"; then
      {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] start.sh: pull --ff-only failed"
        cat "$ERR_FILE" 2>/dev/null || true
      } >> "$LOG_FILE"
    fi
    rm -f "$ERR_FILE"
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

# 空白 / スラッシュ / 危険文字を除去
REPO=$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9._-' '-')
# パストラバーサル対策: 2文字以上の連続ドットを - に置換し、先頭のドットも除去
REPO=$(printf '%s' "$REPO" | sed 's/\.\.\+/-/g; s/^\.//')
# サニタイズ後に空になった場合のフォールバック
[ -z "$REPO" ] && REPO="unknown"

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

# memory ファイルから注入マーカー行を除去する (プロンプトインジェクション対策)
# begin/end マーカーが混入すると次の session で awk フィルタを破壊し、
# 攻撃コンテンツが CLAUDE.md に残留する可能性がある。
# -x (行全体一致) を外してマーカー文字列を「含む」行を全除去することで、
# 前後スペースや埋め込みケースも防ぐ。
sanitize_memory() {
  local path="$1"
  grep -v -F \
    -e "$INJECT_BEGIN" \
    -e "$INJECT_END" \
    "$path" 2>/dev/null || true
}

# 注入ブロック生成用と CLAUDE.md 合成用の tmpfile を先に両方作成し、
# EXIT trap を一度だけ設定する (2回定義すると後者が前者を上書きするため)
TMPFILE=$(mktemp "${TMPDIR:-/tmp}/cms-inject.XXXXXX")
FINAL_TMP=$(mktemp "${TMPDIR:-/tmp}/cms-claude-md.XXXXXX")
trap 'rm -f "$TMPFILE" "$FINAL_TMP"' EXIT
{
  echo "$INJECT_BEGIN"
  echo "<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->"
  echo ""

  if [ -f "$GLOBAL" ]; then
    echo "## グローバル設計方針"
    echo ""
    sanitize_memory "$GLOBAL"
    echo ""
  fi

  if [ -f "$PROJECT" ]; then
    echo "## プロジェクト固有の記憶 (${REPO})"
    echo ""
    sanitize_memory "$PROJECT"
    echo ""
  fi

  echo "$INJECT_END"
} > "$TMPFILE"

# 既存の注入ブロックを削除してから新ブロックをアトミックに書き込む
# cleanup → tmpfile 合成 → mv の順で、クラッシュ時に中途半端な状態を残さない
if [ -f "$CLAUDE_MD" ]; then
  bash "$SKILL_DIR/hooks/cleanup.sh" >/dev/null 2>&1 || true
  if [ -s "$CLAUDE_MD" ]; then
    if [ "$(tail -c 1 "$CLAUDE_MD" 2>/dev/null | od -An -tx1 | tr -d ' ')" != "0a" ]; then
      printf '\n' >> "$CLAUDE_MD"
    fi
  fi
  cat "$CLAUDE_MD" "$TMPFILE" > "$FINAL_TMP"
else
  cat "$TMPFILE" > "$FINAL_TMP"
fi

mv "$FINAL_TMP" "$CLAUDE_MD"
