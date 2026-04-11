#!/usr/bin/env node
// claude-memory-sync: uninstall
// settings.json から hook を削除し、注入ブロックをクリーンアップする

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { execSync } from 'child_process';
import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(__dirname);
const SETTINGS_PATH = join(homedir(), '.claude', 'settings.json');
const HOOK_CLEANUP = join(SKILL_DIR, 'hooks', 'cleanup.sh');

if (!existsSync(SETTINGS_PATH)) {
  console.log('settings.json が存在しません。スキップします。');
  process.exit(0);
}

let settings = {};
try {
  settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
} catch {
  console.error('❌ settings.json のパースに失敗しました');
  process.exit(1);
}

// memory-sync の hook エントリを削除
for (const event of ['UserPromptSubmit', 'Stop']) {
  if (settings.hooks?.[event]) {
    settings.hooks[event] = settings.hooks[event].filter(
      h => !h.hooks?.some(hh => hh.command?.includes('memory-sync'))
    );
  }
}

writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
console.log('✓ hook を settings.json から削除しました');

// CLAUDE.md の注入ブロックをクリーンアップ
try {
  execSync(`bash "${HOOK_CLEANUP}"`, { stdio: 'inherit' });
} catch {
  // cleanup は失敗してもアンインストール自体は続行
}

console.log('');
console.log('✓ アンインストール完了');
console.log('  記憶リポジトリ (~/.claude-memory) は削除されていません');
console.log('  必要であれば手動で削除してください');
