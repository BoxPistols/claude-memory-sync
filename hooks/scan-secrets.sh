#!/bin/bash
# claude-memory-sync: scan-secrets
# 記憶リポジトリの未コミット変更に対して、よく知られたシークレット
# パターンが含まれていないか簡易スキャンする。
#
# 終了コード:
#   0  問題なし (commit を続行)
#   1  シークレットっぽいパターンを検出 (commit を中止)
#
# 想定呼び出し元: hooks/stop.sh (commit 前) / bin/cm (push 前)
#
# このスキャナは **best-effort** であり、網羅性は保証しない。真剣な
# シークレット検出には trufflehog / gitleaks 等を併用すること。本スクリプ
# トの狙いは「明らかにまずい典型パターンだけでも早期に捕まえる」こと。

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"

if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# 追加/変更された行だけをスキャン対象にする (削除行は無視)
DIFF=$(git diff --cached --unified=0 2>/dev/null; git diff --unified=0 2>/dev/null)
DIFF+=$(git ls-files --others --exclude-standard 2>/dev/null | while read -r f; do
  [ -f "$f" ] && cat "$f"
done)

if [ -z "$DIFF" ]; then
  exit 0
fi

# シークレットパターン (grep -E 用)
# - OpenAI / Anthropic / Google / AWS / GitHub / Slack / Stripe / JWT / PEM
PATTERNS=(
  'sk-[A-Za-z0-9_-]{20,}'           # OpenAI / Anthropic API key
  'ghp_[A-Za-z0-9]{30,}'            # GitHub personal access token (classic)
  'github_pat_[A-Za-z0-9_]{60,}'    # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                # AWS access key ID
  'AIza[0-9A-Za-z_-]{35}'           # Google API key
  'xox[baprs]-[0-9A-Za-z-]{20,}'    # Slack token
  'rk_live_[0-9A-Za-z]{20,}'        # Stripe restricted key
  'sk_live_[0-9A-Za-z]{20,}'        # Stripe secret key
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'  # JWT (3 segs)
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key
  'hf_[A-Za-z0-9]{30,}'             # Hugging Face token
)

FOUND=0
for pat in "${PATTERNS[@]}"; do
  # -e で明示的にパターンとして渡す (-----BEGIN ... がオプション扱いされるのを防ぐ)
  if printf '%s' "$DIFF" | grep -E -q -e "$pat"; then
    if [ "$FOUND" -eq 0 ]; then
      echo "" >&2
      echo "⚠️  claude-memory-sync: potential secret detected in pending changes" >&2
      echo "" >&2
    fi
    echo "  match: $pat" >&2
    FOUND=1
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "" >&2
  echo "  commit was aborted to avoid leaking secrets." >&2
  echo "  review and clean up the staged files, then re-run 'cm' manually." >&2
  echo "  to force-commit anyway, set CLAUDE_MEMORY_SKIP_SECRET_SCAN=1." >&2
  echo "" >&2

  # エスケープハッチ — 明示的に上書き指定された場合は通す
  case "${CLAUDE_MEMORY_SKIP_SECRET_SCAN:-}" in
    1|true|TRUE|yes|YES)
      echo "  (CLAUDE_MEMORY_SKIP_SECRET_SCAN set — continuing despite warning)" >&2
      exit 0
      ;;
  esac
  exit 1
fi

exit 0
