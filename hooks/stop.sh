#!/bin/bash
# claude-memory-sync: stop hook
# Claude Code セッション終了時に記憶リポジトリを自動 push する

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"

# 記憶リポジトリが存在しない、またはGit管理されていない場合はスキップ
if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# 変更がなければスキップ
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

REPO=$(basename "$(pwd)")
TIMESTAMP=$(date '+%m/%d %H:%M')

git add .
git commit -m "auto: ${REPO} ${TIMESTAMP}" --quiet
git push --quiet 2>/dev/null || true
