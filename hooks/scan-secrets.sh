#!/bin/bash
# claude-memory-sync: scan-secrets
# 記憶リポジトリの変更内容に対して、よく知られたシークレット
# パターンが含まれていないか簡易スキャンする。
#
# 2 つのモード:
#   (default)                          未 commit 差分 + untracked を scan
#   CLAUDE_MEMORY_SCAN_MODE=history    未 push commit の diff を scan
#
# 終了コード:
#   0  問題なし (commit を続行)
#   1  シークレットっぽいパターンを検出 (commit を中止)
#
# 想定呼び出し元:
#   - hooks/stop.sh (commit 前)  — default mode
#   - bin/cm sync    (commit 前)  — default mode
#   - bin/cm sync    (push 前)    — history mode
#
# このスキャナは **best-effort** であり、網羅性は保証しない。真剣な
# シークレット検出には trufflehog / gitleaks 等を併用すること。本スクリプ
# トの狙いは「明らかにまずい典型パターンだけでも早期に捕まえる」こと。

set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude-memory}"
MODE="${CLAUDE_MEMORY_SCAN_MODE:-working}"

if [ ! -d "$MEMORY_DIR/.git" ]; then
  exit 0
fi

cd "$MEMORY_DIR"

# ── スキャン対象を決定 ───────────────────────────────────────

gather_diff_working() {
  # staged/unstaged diff + untracked ファイルの全文
  git diff --cached --unified=0 2>/dev/null || true
  git diff --unified=0 2>/dev/null || true
  git ls-files --others --exclude-standard 2>/dev/null | while read -r f; do
    [ -f "$f" ] && cat "$f"
  done
}

gather_diff_history() {
  # 上流ブランチに対する未 push commit の diff を scan する。
  # 上流未設定なら all commits を scan する (初回 push 用)。
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    # 未 push commit のみ
    git log --pretty=format: -p '@{u}..HEAD' 2>/dev/null || true
  else
    # 上流未設定 = 初回 push 想定、全 commit
    git log --pretty=format: -p 2>/dev/null || true
  fi
}

case "$MODE" in
  working)
    DIFF=$(gather_diff_working)
    SCAN_TARGET="pending changes"
    ;;
  history)
    DIFF=$(gather_diff_history)
    SCAN_TARGET="unpushed commits"
    ;;
  *)
    echo "[scan-secrets] unknown mode: $MODE" >&2
    exit 2
    ;;
esac

if [ -z "$DIFF" ]; then
  exit 0
fi

# ── シークレットパターン (grep -E 用) ───────────────────────
#
# 追加時は best-effort かつ false positive が少ないパターンだけを選ぶ。
# プレフィックス + 十分な長さの base62 文字列、という形が理想。
PATTERNS=(
  # OpenAI / Anthropic
  'sk-[A-Za-z0-9_-]{20,}'
  'sk_live_[0-9A-Za-z]{20,}'         # Stripe 秘密鍵
  'rk_live_[0-9A-Za-z]{20,}'         # Stripe restricted key

  # GitHub
  'ghp_[A-Za-z0-9]{30,}'             # personal access token (classic)
  'gho_[A-Za-z0-9]{30,}'             # OAuth token
  'ghu_[A-Za-z0-9]{30,}'             # user-to-server token
  'ghs_[A-Za-z0-9]{30,}'             # server-to-server token
  'ghr_[A-Za-z0-9]{30,}'             # refresh token
  'github_pat_[A-Za-z0-9_]{60,}'     # fine-grained PAT

  # Cloud (AWS / GCP / Azure)
  'AKIA[0-9A-Z]{16}'                 # AWS access key ID
  'ASIA[0-9A-Z]{16}'                 # AWS temporary access key
  'AIza[0-9A-Za-z_-]{35}'            # Google API key
  'GOCSPX-[A-Za-z0-9_-]{20,}'        # Google OAuth client secret
  'DefaultEndpointsProtocol=.*AccountKey='  # Azure Storage connection string

  # メッセージング / チャット
  'xox[baprs]-[0-9A-Za-z-]{20,}'     # Slack token
  'T[0-9A-Z]{8,}/B[0-9A-Z]{8,}/[0-9A-Za-z]{20,}'  # Slack webhook (team/bot/key)

  # 機械学習 / AI プラットフォーム
  'hf_[A-Za-z0-9]{30,}'              # Hugging Face
  'r8_[A-Za-z0-9]{30,}'              # Replicate

  # パッケージマネージャ / レジストリ
  'npm_[A-Za-z0-9]{30,}'             # npm access token
  'dckr_pat_[A-Za-z0-9_-]{20,}'      # Docker Hub

  # インフラ / 開発プラットフォーム
  'dop_v1_[a-f0-9]{60,}'             # DigitalOcean token
  'dapi[a-f0-9]{30,}'                # Databricks PAT
  'shpat_[a-f0-9]{30,}'              # Shopify access token
  'shpca_[a-f0-9]{30,}'              # Shopify custom app
  'glpat-[A-Za-z0-9_-]{20,}'         # GitLab PAT
  'xoxe.xoxp-[0-9]-[A-Za-z0-9-]{100,}'  # Slack user refresh token

  # 汎用
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'  # JWT
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key (RSA / EC / OPENSSH)
)

FOUND=0
for pat in "${PATTERNS[@]}"; do
  # -e で明示的にパターンとして渡す (-----BEGIN ... がオプション扱いされるのを防ぐ)
  if printf '%s' "$DIFF" | grep -E -q -e "$pat"; then
    if [ "$FOUND" -eq 0 ]; then
      echo "" >&2
      echo "⚠️  claude-memory-sync: potential secret detected in ${SCAN_TARGET}" >&2
      echo "" >&2
    fi
    echo "  match: $pat" >&2
    FOUND=1
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "" >&2
  echo "  operation was aborted to avoid leaking secrets." >&2
  if [ "$MODE" = "working" ]; then
    echo "  review and clean up the staged files, then re-run." >&2
  else
    echo "  review git log -p, fix the offending commit(s) with" >&2
    echo "  'git rebase -i' or 'git reset --soft <rev>', then re-run." >&2
  fi
  echo "  to force-continue anyway, set CLAUDE_MEMORY_SKIP_SECRET_SCAN=1." >&2
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
