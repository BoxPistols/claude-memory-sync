#!/bin/bash
# claude-memory-sync: stop hook
# 応答の終わり(Stop)とセッション終了(SessionEnd)に記憶リポジトリをcommitする。pushはデフォルトoff。
#
# 環境変数:
#   CLAUDE_MEMORY_DIR            記憶リポジトリのパス (デフォルト: ~/.claude-memory)
#   CLAUDE_MEMORY_AUTO_PUSH      "1" / "true" で自動 push を有効化 (デフォルト: 無効)
#   CLAUDE_MEMORY_PUSH_INTERVAL  Stopでのpushの最短間隔(秒、デフォルト: 600)
#   CLAUDE_MEMORY_FINAL          "1" のとき間隔に関係なくpushする(SessionEnd用)
#
# Stopでも間隔を空けてpushするのは、ターミナルを閉じたときにSessionEndが最後まで
# 走る保証がないため。失うのは最後の最大INTERVAL秒ぶんで、それも手元にはcommit済みで残る。
#
# デフォルトで自動 push を無効にしているのは、Claude が誤って API key / token /
# コード断片を記憶ファイルに書き込んだ場合に、意図せずリモートへ漏洩することを
# 防ぐため。変更を push するときは `cm` を明示的に実行すること。

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/claude-memory-sync.log"

# MEMORY_DIR が HOME 以下にあることを確認 (任意パス操作の防止)
case "$MEMORY_DIR" in
  "$HOME/"*|"$HOME")
    ;;
  *)
    echo "[claude-memory-sync] CLAUDE_MEMORY_DIR は \$HOME 以下に設定してください: $MEMORY_DIR" >&2
    exit 1
    ;;
esac

# 記憶リポジトリが存在しない、または Git 管理されていない場合はスキップ
if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# ログディレクトリを確保
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR" 2>/dev/null || true

# ログローテーション: 1MB 超えで古いログを退避 (スキャン前に実行して書き込み領域を確保)
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

# 変更がある時だけcommitする(未pushのcommitが残っていれば、変更がなくてもpushへ進む)
if [ -n "$(git status --porcelain)" ]; then
  # Secret scanner — 変更・新規ファイルに対して簡易パターンマッチ
  # 検出したら commit を中止 (手動介入必須)
  if [ -x "$SKILL_DIR/hooks/scan-secrets.sh" ]; then
    if ! "$SKILL_DIR/hooks/scan-secrets.sh"; then
      # シークレット検出は異常事態 — ログに記録して非ゼロで終了
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] stop.sh: commit aborted — potential secret detected" >> "$LOG_FILE"
      exit 1
    fi
  fi

  REPO=$(basename "$(pwd)")
  TIMESTAMP=$(date '+%m/%d %H:%M')

  # .md ファイルのみをステージング (意図しないファイルの commit を防ぐ)
  # -A は untracked ディレクトリ配下の新規 .md も拾うために必要。
  # pathspec '*.md' により .env など他形式は除外される。
  git add -A -- '*.md'

  # .md 以外の変更のみの場合はステージング対象がなく commit 不要
  if [ -n "$(git diff --cached --name-only)" ]; then
    git commit -m "auto: ${REPO} ${TIMESTAMP}" --quiet
  fi
fi

# 自動 push はデフォルト off — 明示的に opt-in された場合のみ実行
AUTO_PUSH="${CLAUDE_MEMORY_AUTO_PUSH:-}"
case "$AUTO_PUSH" in
  1|true|TRUE|yes|YES)
    # upstreamより先行しているcommitがなければ何もしない
    AHEAD=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    [ "$AHEAD" -gt 0 ] || exit 0
    # Stopでは前回のpushからINTERVAL秒経つまで待つ。SessionEnd (FINAL)は常にpushする
    STAMP="$LOG_DIR/claude-memory-sync.last-push"
    if [ "${CLAUDE_MEMORY_FINAL:-}" != "1" ] && [ -f "$STAMP" ]; then
      LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
      [ $(( $(date +%s) - LAST )) -ge "${CLAUDE_MEMORY_PUSH_INTERVAL:-600}" ] || exit 0
    fi
    if git remote | grep -q .; then
      # ネットワーク障害やリモート競合で session 終了を止めないよう || true
      # エラー内容は自ユーザ領域のログに残す
      ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/cms-push.XXXXXX")
      # 他のマシンが先にpushしていたら1回だけrebaseして再試行する。競合したらrebaseを戻してログに残す
      PUSHED=0
      if git push --quiet 2>"$ERR_FILE"; then
        PUSHED=1
      elif git pull --rebase --quiet 2>>"$ERR_FILE"; then
        git push --quiet 2>>"$ERR_FILE" && PUSHED=1
      else
        git rebase --abort 2>/dev/null || true
      fi
      if [ "$PUSHED" = 1 ]; then
        date +%s > "$STAMP"
      else
        {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] stop.sh: auto push failed"
          cat "$ERR_FILE" 2>/dev/null || true
        } >> "$LOG_FILE"
      fi
      rm -f "$ERR_FILE"
    fi
    ;;
esac
