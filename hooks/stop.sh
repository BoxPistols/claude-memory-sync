#!/bin/bash
# claude-memory-sync: stop hook
# セッション終了時に記憶リポジトリを commit する。push はデフォルト off。
#
# 環境変数:
#   CLAUDE_MEMORY_DIR        記憶リポジトリのパス (デフォルト: ~/.claude-memory)
#   CLAUDE_MEMORY_AUTO_PUSH  "1" / "true" で自動 push を有効化 (デフォルト: 無効)
#
# デフォルトで自動 push を無効にしているのは、Claude が誤って API key / token /
# コード断片を記憶ファイルに書き込んだ場合に、意図せずリモートへ漏洩することを
# 防ぐため。変更を push するときは `cm` を明示的に実行すること。

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 記憶リポジトリが存在しない、または Git 管理されていない場合はスキップ
if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# 変更がなければスキップ
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

# Secret scanner — 変更・新規ファイルに対して簡易パターンマッチ
# 検出したら commit を中止 (手動介入必須)
if [ -x "$SKILL_DIR/hooks/scan-secrets.sh" ]; then
  if ! "$SKILL_DIR/hooks/scan-secrets.sh"; then
    # scan-secrets.sh が非ゼロを返したら commit せず終了
    exit 0
  fi
fi

REPO=$(basename "$(pwd)")
TIMESTAMP=$(date '+%m/%d %H:%M')

git add .
git commit -m "auto: ${REPO} ${TIMESTAMP}" --quiet

# 自動 push はデフォルト off — 明示的に opt-in された場合のみ実行
AUTO_PUSH="${CLAUDE_MEMORY_AUTO_PUSH:-}"
case "$AUTO_PUSH" in
  1|true|TRUE|yes|YES)
    if git remote | grep -q .; then
      # ネットワーク障害やリモート競合で session 終了を止めないよう || true
      git push --quiet 2>/dev/null || true
    fi
    ;;
esac
