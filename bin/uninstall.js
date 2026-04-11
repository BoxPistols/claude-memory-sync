#!/usr/bin/env node
// claude-memory-sync: uninstall
// settings.json から claude-memory-sync 所有の hook を削除し、
// ~/.claude/CLAUDE.md の注入ブロックをクリーンアップする。
//
// ユーザーが独自に足した無関係な hook は一切触らない。

import { readFileSync, writeFileSync, existsSync, renameSync, chmodSync } from 'fs';
import { execFileSync } from 'child_process';
import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(__dirname);
const SETTINGS_PATH = join(homedir(), '.claude', 'settings.json');
const HOOK_CLEANUP = join(SKILL_DIR, 'hooks', 'cleanup.sh');

// claude-memory-sync が所有する hook を識別するマーカー
const MARKER = '_claude_memory_sync';

if (!existsSync(SETTINGS_PATH)) {
  console.log('settings.json が存在しません。スキップします。');
} else {
  let settings = {};
  try {
    settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf-8'));
  } catch {
    console.error('[error] settings.json のパースに失敗しました');
    process.exit(1);
  }

  // marker-based 除去 (新方式) + レガシー command 文字列マッチ (後方互換)
  for (const event of Object.keys(settings.hooks ?? {})) {
    const list = settings.hooks[event];
    if (!Array.isArray(list)) continue;

    const remaining = list.filter((entry) => {
      // マーカーが付いていれば削除
      if (entry[MARKER]) return false;
      // レガシー: memory-sync 文字列を含む command は削除 (後方互換)
      const hasLegacyCmd = (entry.hooks ?? []).some((h) =>
        (h.command ?? '').includes('memory-sync')
      );
      return !hasLegacyCmd;
    });

    if (remaining.length === 0) {
      delete settings.hooks[event];
    } else {
      settings.hooks[event] = remaining;
    }
  }

  // Atomic write (setup.js と同じパターン)
  const tmpPath = `${SETTINGS_PATH}.tmp.${process.pid}`;
  writeFileSync(tmpPath, JSON.stringify(settings, null, 2) + '\n');
  try {
    chmodSync(tmpPath, 0o600);
  } catch {
    // chmod 失敗は致命的ではない
  }
  renameSync(tmpPath, SETTINGS_PATH);
  console.log('ok hook を settings.json から削除しました');
}

// CLAUDE.md の注入ブロックをクリーンアップ
// execFileSync を使うことで shell 解釈を挟まず、引数を確実に分離する
try {
  execFileSync('bash', [HOOK_CLEANUP], { stdio: 'inherit' });
} catch {
  // cleanup は失敗してもアンインストール自体は続行
}

console.log('');
console.log('ok アンインストール完了');
console.log('  記憶リポジトリ (~/.claude-memory) は削除されていません');
console.log('  必要であれば手動で削除してください');
