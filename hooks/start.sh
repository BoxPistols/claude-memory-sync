#!/bin/bash
# claude-memory-sync: start hook
# 記憶を 2 箇所に分けて注入する。
#   - global.md          → ~/.claude/CLAUDE.md            (全プロジェクト共通)
#   - repos/<key>.md     → <project-root>/CLAUDE.local.md (そのプロジェクト限定)
#
# プロジェクト固有分を ~/.claude/CLAUDE.md に入れない理由:
#   ~/.claude/CLAUDE.md はマシン上の全 Claude Code セッションが共有する単一ファイルで、
#   本フックは UserPromptSubmit ごとに全体を書き換える。複数リポジトリで同時に
#   セッションを開いていると後勝ちで上書きされ、別リポジトリの記憶が混入する。
#   プロジェクト直下の CLAUDE.local.md へ書けば注入先がセッションごとに分かれ、
#   この競合が構造的に消える (CLAUDE.local.md は CLAUDE.md の直後に読まれる公式の仕組み)。
#
# プロジェクトのリポジトリを汚さないための配慮:
#   CLAUDE.local.md が git 管理下に入らないよう、未 ignore なら .git/info/exclude へ
#   追記してから書き込む (追跡対象の .gitignore は書き換えない)。
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
# 旧 v0.0.x マーカー。cleanup.sh がこの行以降を全削除するため、memory 本文
# 経由で注入されると CLAUDE.md の後続内容が破壊される。サニタイズ対象に含める。
LEGACY_MARKER="<!-- claude-memory-sync: auto-generated -->"
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

# プロジェクト固有の記憶の注入先 (<project-root>/CLAUDE.local.md)
project_root() {
  local root
  if root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
    printf '%s' "$root"
    return
  fi
  printf '%s' "$PWD"
}
PROJECT_ROOT=$(project_root)
PROJECT_MD="$PROJECT_ROOT/CLAUDE.local.md"

# CLAUDE.local.md が誤って commit されないよう、未 ignore なら .git/info/exclude へ追記する。
# .git/info/exclude はクローカルかつ追跡対象外なので、ユーザーのリポジトリを汚さない。
ensure_local_ignored() {
  local git_dir
  # --git-dir ではなく --git-common-dir を使う。
  # linked worktree では --git-dir が per-worktree の .git/worktrees/<name> を返すが、
  # git が info/exclude を読むのは common dir 側なので、そちらに書かないと無視が効かない
  # (実測: per-worktree 側に書くと worktree で git status に出てしまう)。
  git_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -n "$git_dir" ] || return 0
  case "$git_dir" in
    /*) ;;
    *) git_dir="$PROJECT_ROOT/$git_dir" ;;
  esac
  # 既に .gitignore 等で無視されているなら何もしない
  if git -C "$PROJECT_ROOT" check-ignore -q "CLAUDE.local.md" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$git_dir/info" 2>/dev/null || return 0
  # gitignore 構文は行末のインラインコメントを解釈しない。
  # "CLAUDE.local.md # comment" と書くとコメント込みの文字列がパターンになり効かない。
  # コメントは必ず独立行に置くこと。
  if ! grep -qxF "CLAUDE.local.md" "$git_dir/info/exclude" 2>/dev/null; then
    {
      echo "# added by claude-memory-sync"
      echo "CLAUDE.local.md"
    } >> "$git_dir/info/exclude" 2>/dev/null || true
  fi
}

# 注入する内容がなければ両方の注入先から既存ブロックを削除して終了
if [ ! -f "$GLOBAL" ] && [ ! -f "$PROJECT" ]; then
  [ -f "$CLAUDE_MD" ] && bash "$SKILL_DIR/hooks/cleanup.sh" "$CLAUDE_MD" >/dev/null 2>&1 || true
  [ -f "$PROJECT_MD" ] && bash "$SKILL_DIR/hooks/cleanup.sh" "$PROJECT_MD" >/dev/null 2>&1 || true
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
    -e "$LEGACY_MARKER" \
    "$path" 2>/dev/null || true
}

# 注入ブロック生成用と CLAUDE.md 合成用の tmpfile を先に両方作成し、
# EXIT trap を一度だけ設定する (2回定義すると後者が前者を上書きするため)
TMPFILE=$(mktemp "${TMPDIR:-/tmp}/cms-inject.XXXXXX")
FINAL_TMP=$(mktemp "${TMPDIR:-/tmp}/cms-claude-md.XXXXXX")
trap 'rm -f "$TMPFILE" "$FINAL_TMP"' EXIT

# 既存の注入ブロックを削除してから新ブロックをアトミックに書き込む。
# cleanup → tmpfile 合成 → mv の順で、クラッシュ時に中途半端な状態を残さない。
# $1 = 注入先ファイル / $2 = 注入ブロックを書き出した tmpfile
# 内容が前回と同じなら書き込みをスキップする。
# CLAUDE.md 系はセッション開始時に読まれるもので、UserPromptSubmit ごとに
# 書き換えても現セッションのコンテキストは変わらない。無駄な write は
# 他セッションとの競合の窓を広げるだけなので、変化時のみ書く。
block_unchanged() {
  local target="$1" block="$2"
  [ -f "$target" ] || return 1
  # 既存ファイルから注入ブロックだけを抜き出して比較する
  local cur
  cur=$(awk -v begin="$INJECT_BEGIN" -v end="$INJECT_END" '
    $0 == begin { inside = 1 }
    inside { print }
    inside && $0 == end { inside = 0 }
  ' "$target" 2>/dev/null || true)
  [ "$cur" = "$(cat "$block")" ]
}

inject_into() {
  local target="$1" block="$2"
  if block_unchanged "$target" "$block"; then
    return 0
  fi
  bash "$SKILL_DIR/hooks/cleanup.sh" "$target" >/dev/null 2>&1 || true
  if [ -f "$target" ] && [ -s "$target" ]; then
    if [ "$(tail -c 1 "$target" 2>/dev/null | od -An -tx1 | tr -d ' ')" != "0a" ]; then
      printf '\n' >> "$target"
    fi
    cat "$target" "$block" > "$FINAL_TMP"
  else
    cat "$block" > "$FINAL_TMP"
  fi
  mv "$FINAL_TMP" "$target"
  # 次の inject_into 呼び出しに備えて tmpfile を作り直す (trap の対象を維持)
  FINAL_TMP=$(mktemp "${TMPDIR:-/tmp}/cms-claude-md.XXXXXX")
}

# ── グローバル記憶 → ~/.claude/CLAUDE.md ──
if [ -f "$GLOBAL" ]; then
  {
    echo "$INJECT_BEGIN"
    echo "<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->"
    echo ""
    echo "## グローバル設計方針"
    echo ""
    sanitize_memory "$GLOBAL"
    echo ""
    echo "$INJECT_END"
  } > "$TMPFILE"
  inject_into "$CLAUDE_MD" "$TMPFILE"
else
  # global.md が消えた場合は残骸を掃除する
  [ -f "$CLAUDE_MD" ] && bash "$SKILL_DIR/hooks/cleanup.sh" "$CLAUDE_MD" >/dev/null 2>&1 || true
fi

# ── プロジェクト固有の記憶 → <project-root>/CLAUDE.local.md ──
# 書き込めない場所 (読み取り専用・$HOME 直下等) では黙って諦めずログに残す
if [ -f "$PROJECT" ]; then
  if [ -w "$PROJECT_ROOT" ] || [ -w "$PROJECT_MD" ]; then
    ensure_local_ignored
    {
      echo "$INJECT_BEGIN"
      echo "<!-- 自動生成 / 編集不要 / claude-memory-sync が管理 -->"
      echo ""
      echo "## プロジェクト固有の記憶 (${REPO})"
      echo ""
      sanitize_memory "$PROJECT"
      echo ""
      echo "$INJECT_END"
    } > "$TMPFILE"
    inject_into "$PROJECT_MD" "$TMPFILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] start.sh: $PROJECT_ROOT に書き込めないためプロジェクト記憶の注入をスキップ" >> "$LOG_FILE"
  fi
else
  # このプロジェクトの記憶が無い場合、前回の残骸を掃除する
  [ -f "$PROJECT_MD" ] && bash "$SKILL_DIR/hooks/cleanup.sh" "$PROJECT_MD" >/dev/null 2>&1 || true
fi
