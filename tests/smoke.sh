#!/bin/bash
# CI の smoke test (.github/workflows/ci.yml) と同じシナリオをローカルで一括実行する。
# hooks は CLAUDE_MEMORY_DIR が $HOME 以下であることを要求し、~/.claude にも書き込むため、
# HOME を一時ディレクトリに差し替えて実環境の記憶・設定に触れないようにしている。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cms-smoke.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME"
# 開発者の global git 設定 (署名必須など) に結果が左右されないよう隔離する
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
git config --global user.email test@example.com
git config --global user.name Tester
git config --global init.defaultBranch main
export CLAUDE_MEMORY_DIR="$HOME/.claude-memory"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

new_memory_repo() {
  rm -rf "$CLAUDE_MEMORY_DIR"
  mkdir -p "$CLAUDE_MEMORY_DIR"
  git -C "$CLAUDE_MEMORY_DIR" init -q
  echo 'safe content' > "$CLAUDE_MEMORY_DIR/global.md"
  git -C "$CLAUDE_MEMORY_DIR" add global.md
  git -C "$CLAUDE_MEMORY_DIR" commit -q -m "initial test fixture"
}

committed_in_head() {
  git -C "$CLAUDE_MEMORY_DIR" log -1 --name-only --format= | grep -qx "$1"
}

# ── scan-secrets ──
new_memory_repo
if bash "$REPO_ROOT/hooks/scan-secrets.sh" >/dev/null 2>&1; then ok "scan-secrets: clean changes pass"; else ng "scan-secrets: clean changes pass"; fi

echo 'leaked: sk-proj-abcdef1234567890abcdef1234567890' >> "$CLAUDE_MEMORY_DIR/global.md"
if bash "$REPO_ROOT/hooks/scan-secrets.sh" >/dev/null 2>&1; then ng "scan-secrets: detects OpenAI-style key"; else ok "scan-secrets: detects OpenAI-style key"; fi
if CLAUDE_MEMORY_SKIP_SECRET_SCAN=1 bash "$REPO_ROOT/hooks/scan-secrets.sh" >/dev/null 2>&1; then ok "scan-secrets: bypass flag allows commit"; else ng "scan-secrets: bypass flag allows commit"; fi
git -C "$CLAUDE_MEMORY_DIR" checkout -q -- global.md

printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEow==\n-----END RSA PRIVATE KEY-----\n' >> "$CLAUDE_MEMORY_DIR/global.md"
if bash "$REPO_ROOT/hooks/scan-secrets.sh" >/dev/null 2>&1; then ng "scan-secrets: detects PEM key"; else ok "scan-secrets: detects PEM key"; fi
git -C "$CLAUDE_MEMORY_DIR" checkout -q -- global.md

# ── stop.sh: commit 対象の選別 ──
new_memory_repo
mkdir -p "$CLAUDE_MEMORY_DIR/repos"
echo '# new project memory' > "$CLAUDE_MEMORY_DIR/repos/new.md"
bash "$REPO_ROOT/hooks/stop.sh" </dev/null >/dev/null 2>&1 || true
if committed_in_head repos/new.md; then ok "stop.sh: commits .md in untracked subdir"; else ng "stop.sh: commits .md in untracked subdir"; fi

rm "$CLAUDE_MEMORY_DIR/global.md"
bash "$REPO_ROOT/hooks/stop.sh" </dev/null >/dev/null 2>&1 || true
if git -C "$CLAUDE_MEMORY_DIR" cat-file -e HEAD:global.md 2>/dev/null; then ng "stop.sh: commits deletion of tracked .md"; else ok "stop.sh: commits deletion of tracked .md"; fi

echo 'SECRET=should_not_be_committed' > "$CLAUDE_MEMORY_DIR/.env"
echo '# another memory' > "$CLAUDE_MEMORY_DIR/repos/another.md"
bash "$REPO_ROOT/hooks/stop.sh" </dev/null >/dev/null 2>&1 || true
if git -C "$CLAUDE_MEMORY_DIR" log --all --name-only --format= | grep -qx '.env'; then ng "stop.sh: never commits non-.md untracked files"; else ok "stop.sh: never commits non-.md untracked files"; fi
if committed_in_head repos/another.md; then ok "stop.sh: commits new .md alongside"; else ng "stop.sh: commits new .md alongside"; fi

# ── cm sync: clean tree でも未 push の commit を push する ──
rm -rf "$CLAUDE_MEMORY_DIR"
git init -q --bare "$SANDBOX/remote.git"
git clone -q "$SANDBOX/remote.git" "$CLAUDE_MEMORY_DIR" 2>/dev/null
git -C "$CLAUDE_MEMORY_DIR" commit -q --allow-empty -m "initial"
git -C "$CLAUDE_MEMORY_DIR" push -q -u origin HEAD 2>/dev/null
echo '# memory' > "$CLAUDE_MEMORY_DIR/global.md"
bash "$REPO_ROOT/hooks/stop.sh" </dev/null >/dev/null 2>&1 || true
bash "$REPO_ROOT/bin/cm" sync >/dev/null 2>&1 || true
if [ "$(git -C "$CLAUDE_MEMORY_DIR" rev-list --count '@{u}..HEAD')" -eq 0 ]; then ok "cm sync: pushes commits left by stop.sh"; else ng "cm sync: pushes commits left by stop.sh"; fi

# ── start.sh: 注入先の分離 (global → ~/.claude/CLAUDE.md, repos → CLAUDE.local.md) ──
mkdir -p "$CLAUDE_MEMORY_DIR/repos" "$HOME/.claude" "$HOME/work/my-app"
echo '- global rule marker' > "$CLAUDE_MEMORY_DIR/global.md"
echo '- project rule marker' > "$CLAUDE_MEMORY_DIR/repos/github.com-you-my-app.md"
echo '# hand-written' > "$HOME/.claude/CLAUDE.md"
git -C "$HOME/work/my-app" init -q
git -C "$HOME/work/my-app" remote add origin git@github.com:you/my-app.git
( cd "$HOME/work/my-app" && CLAUDE_MEMORY_PULL_TIMEOUT=1 bash "$REPO_ROOT/hooks/start.sh" </dev/null >/dev/null 2>&1 ) || true
G="$HOME/.claude/CLAUDE.md"
L="$HOME/work/my-app/CLAUDE.local.md"
if grep -q 'global rule marker' "$G" && ! grep -q 'project rule marker' "$G"; then ok "start.sh: global.md goes only to ~/.claude/CLAUDE.md"; else ng "start.sh: global.md goes only to ~/.claude/CLAUDE.md"; fi
if grep -q '# hand-written' "$G"; then ok "start.sh: keeps hand-written CLAUDE.md content"; else ng "start.sh: keeps hand-written CLAUDE.md content"; fi
if [ -f "$L" ] && grep -q 'project rule marker' "$L"; then ok "start.sh: repos/<key>.md goes to <project>/CLAUDE.local.md"; else ng "start.sh: repos/<key>.md goes to <project>/CLAUDE.local.md"; fi
if git -C "$HOME/work/my-app" check-ignore -q CLAUDE.local.md; then ok "start.sh: CLAUDE.local.md is git-ignored via info/exclude"; else ng "start.sh: CLAUDE.local.md is git-ignored via info/exclude"; fi

echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
