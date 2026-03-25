#!/usr/bin/env node
// claude-memory-sync: setup
// ~/.claude/settings.json に hook を登録する

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(__dirname);
const CLAUDE_DIR = join(homedir(), '.claude');
const SETTINGS_PATH = join(CLAUDE_DIR, 'settings.json');

const HOOK_START = join(SKILL_DIR, 'hooks', 'start.sh');
const HOOK_STOP  = join(SKILL_DIR, 'hooks', 'stop.sh');

// settings.json を読み込み（なければ初期化）
let settings = {};
if (existsSync(SETTINGS_PATH)) {
  try {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  } catch {
    console.error('settings.json のパースに失敗しました。バックアップを確認してください。');
    process.exit(1);
  }
}

// hooks セクションを初期化
if (!settings.hooks) settings.hooks = {};

// Start hook（PreToolUse の最初のタイミングで注入）
// Claude Code では UserPromptSubmit が session start に最も近い
if (!settings.hooks.UserPromptSubmit) {
  settings.hooks.UserPromptSubmit = [];
}

const startHookEntry = {
  matcher: '',
  hooks: [{ type: 'command', command: `bash "${HOOK_START}"` }],
};

const stopHookEntry = {
  matcher: '',
  hooks: [{ type: 'command', command: `bash "${HOOK_STOP}"` }],
};

// 重複登録を防ぐ
const alreadyHasStart = settings.hooks.UserPromptSubmit?.some(
  h => h.hooks?.some(hh => hh.command?.includes('memory-sync'))
);
if (!alreadyHasStart) {
  settings.hooks.UserPromptSubmit.push(startHookEntry);
}

if (!settings.hooks.Stop) settings.hooks.Stop = [];
const alreadyHasStop = settings.hooks.Stop?.some(
  h => h.hooks?.some(hh => hh.command?.includes('memory-sync'))
);
if (!alreadyHasStop) {
  settings.hooks.Stop.push(stopHookEntry);
}

// 書き込み
mkdirSync(CLAUDE_DIR, { recursive: true });
writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));

console.log('✓ hook を ~/.claude/settings.json に登録しました');
console.log(`  Start: ${HOOK_START}`);
console.log(`  Stop:  ${HOOK_STOP}`);
