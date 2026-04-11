#!/bin/bash
# claude-memory-sync: stop hook
# セッション終了時に記憶リポジトリを自動コミット・push する

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"

# 記憶リポジトリが存在しない、またはGit管理されていない場合はスキップ
if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# リモートがない場合はコミットのみ
HAS_REMOTE=$(git remote | grep -c . || true)

# 変更がなければスキップ
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

REPO=$(basename "$(pwd)")
TIMESTAMP=$(date '+%m/%d %H:%M')

git add .
git commit -m "auto: ${REPO} ${TIMESTAMP}" --quiet

if [ "$HAS_REMOTE" -gt 0 ]; then
  git push --quiet 2>/dev/null || true
fi
