#!/usr/bin/env node
// claude-memory-sync: setup
// ~/.claude/settings.json に hook を登録する
//
// 重複検知は専用プロパティ `_claude_memory_sync: true` を使って厳密に行う
// ので、ユーザーが別の memory-sync っぽい名前の hook を持っていても
// 干渉しない。

import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, chmodSync } from 'fs';
import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(__dirname);
const CLAUDE_DIR = join(homedir(), '.claude');
const SETTINGS_PATH = join(CLAUDE_DIR, 'settings.json');

const HOOK_START = join(SKILL_DIR, 'hooks', 'start.sh');
const HOOK_STOP = join(SKILL_DIR, 'hooks', 'stop.sh');
const HOOK_CLEANUP = join(SKILL_DIR, 'hooks', 'cleanup.sh');

// settings.json を読み込み (なければ初期化)
let settings = {};
if (existsSync(SETTINGS_PATH)) {
  try {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  } catch {
    console.error('[error] settings.json のパースに失敗しました');
    process.exit(1);
  }
}

if (!settings.hooks) settings.hooks = {};

// claude-memory-sync が所有する hook を識別するマーカー
const MARKER = '_claude_memory_sync';

/**
 * 指定イベントから claude-memory-sync が登録した hook を全て除去する。
 * マーカーで識別するので、ユーザーが別途追加した hook は触らない。
 */
// マーカー導入前に登録されたhookも自分のものとして扱う(再セットアップで二重登録しないため)
function isOwned(entry) {
  if (entry[MARKER]) return true;
  return (entry.hooks ?? []).some((h) => {
    const cmd = h.command ?? '';
    return cmd.includes(HOOK_START) || cmd.includes(HOOK_STOP);
  });
}

function removeOwnedHooks(eventName) {
  const list = settings.hooks[eventName];
  if (!Array.isArray(list)) return;
  settings.hooks[eventName] = list.filter((entry) => !isOwned(entry));
  if (settings.hooks[eventName].length === 0) {
    delete settings.hooks[eventName];
  }
}

/**
 * hook エントリを追加する。必ずマーカー付きで追加し、同じイベントに既にある
 * claude-memory-sync 所有の hook は先に除去する (idempotent)。
 */
function installHook(eventName, hookCommand, extra = {}) {
  if (!settings.hooks[eventName]) settings.hooks[eventName] = [];
  settings.hooks[eventName].push({
    matcher: '',
    hooks: [{ type: 'command', command: hookCommand, ...extra }],
    [MARKER]: true,
  });
}

// --auto-push: 記憶を自動でpushする。環境変数はマシン間で同期されないので、hookのコマンドに埋め込む
const AUTO_PUSH = process.argv.includes('--auto-push');
const PUSH_ENV = AUTO_PUSH ? 'CLAUDE_MEMORY_AUTO_PUSH=1 ' : '';

// ── 各 hook を登録 ─────────────────────────────────────────────
// CLAUDE.mdはセッション開始時と/compact後にしか読まれないので、pullと合成はセッション開始時の1回だけ行う。
// 旧版が登録したUserPromptSubmitのhookもここで除去する
for (const event of Object.keys(settings.hooks)) removeOwnedHooks(event);
// --global-context: global.mdをCLAUDE.mdではなくSessionStartの出力で渡す(pull直後の内容がそのセッションで効く)
const GLOBAL_ENV = process.argv.includes('--global-context') ? 'CLAUDE_MEMORY_GLOBAL_MODE=context ' : '';
installHook('SessionStart', `${GLOBAL_ENV}bash "${HOOK_START}"`);
// 応答の終わり: commitと間隔を空けたpush。応答を待たせないよう非同期
installHook('Stop', `${PUSH_ENV}bash "${HOOK_STOP}"`, { async: true });
// 終了時: 間隔に関係なくpushまで終える
installHook('SessionEnd', `${PUSH_ENV}CLAUDE_MEMORY_FINAL=1 bash "${HOOK_STOP}"`, { timeout: 30 });

// Atomic write: 一時ファイル → rename で差し替える
// writeFileSync だけだと途中クラッシュで settings.json が truncate され、
// Claude Code 起動不能になるリスクがある。
mkdirSync(CLAUDE_DIR, { recursive: true });
const tmpPath = `${SETTINGS_PATH}.tmp.${process.pid}`;
writeFileSync(tmpPath, JSON.stringify(settings, null, 2) + '\n');
try {
  chmodSync(tmpPath, 0o600);  // 機密情報を含む可能性を考慮して 600 に
} catch {
  // chmod 失敗は致命的ではない
}
renameSync(tmpPath, SETTINGS_PATH);  // POSIX atomic rename

console.log('ok hook を ~/.claude/settings.json に登録しました');
console.log(`  SessionStart:     ${HOOK_START}`);
console.log(`  Stop / SessionEnd: ${HOOK_STOP}${AUTO_PUSH ? '  (自動 push 有効)' : ''}`);
console.log(`  cleanup:          ${HOOK_CLEANUP}  (手動実行 / cm clean)`);
