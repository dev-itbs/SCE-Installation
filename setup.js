#!/usr/bin/env node
/**
 * SCE — Ecosystem Clone Script
 *
 * Usage:
 *   node setup.js
 *
 * One-line install (Linux/macOS):
 *   curl -fsSL https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.js | node
 *
 * One-line install (Windows PowerShell):
 *   irm https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.js | node
 */

const { execSync, spawnSync } = require('child_process');
const readline = require('readline');
const path = require('path');
const fs = require('fs');

// ─── Colour helpers ───────────────────────────────────────────────────────────
const c = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  cyan:   '\x1b[36m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  grey:   '\x1b[90m',
};
const log   = msg => console.log(`${c.cyan}${msg}${c.reset}`);
const ok    = msg => console.log(`${c.green}  ✔ ${msg}${c.reset}`);
const warn  = msg => console.log(`${c.yellow}  ⚠ ${msg}${c.reset}`);
const err   = msg => console.log(`${c.red}  ✖ ${msg}${c.reset}`);
const dim   = msg => console.log(`${c.grey}    ${msg}${c.reset}`);
const title = msg => console.log(`\n${c.bold}${c.cyan}${msg}${c.reset}`);
const hr    = ()  => console.log(`${c.grey}${'─'.repeat(60)}${c.reset}`);

// ─── Repository definitions ───────────────────────────────────────────────────
const REPOS = [
  {
    key:    'VaultFlow360',
    label:  'VaultFlow360        (PostgreSQL HA cluster)',
    url:    'https://github.com/dev-itbs/VaultFlow360.git',
    folder: 'VaultFlow360',
  },
  {
    key:    'SCE-Installation',
    label:  'SCE-Installation    (This installer + infra prerequisites)',
    url:    'https://github.com/dev-itbs/SCE-Installation.git',
    folder: 'SCE-Installation',
  },
  {
    key:    'SCE-PHP-SYSTEMS',
    label:  'SCE-PHP-SYSTEMS     (UAC / CRMS / EMS — PHP app)',
    url:    'https://github.com/dev-itbs/SCE-PHP-SYSTEMS.git',
    folder: 'SCE-PHP-SYSTEMS',
  },
  {
    key:    'SCE-Python-Service',
    label:  'SCE-Python-Service  (FastAPI + BullMQ workers)',
    url:    'https://github.com/dev-itbs/SCE-Python-Service.git',
    folder: 'SCE-Python-Service',
  },
  {
    key:    'SCE-Vue-CPA',
    label:  'SCE-Vue-CPA         (Citizen Portal App — Quasar PWA/Android/iOS)',
    url:    'https://github.com/dev-itbs/SCE-Vue-CPA.git',
    folder: 'SCE-Vue-CPA',
  },
  {
    key:    'eAssist-AI-Service',
    label:  'eAssist-AI-Service  (AI assistant — Bun + CopilotKit)',
    url:    'https://github.com/dev-itbs/eAssist-AI-Service.git',
    folder: 'eAssist-AI-Service',
  },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────
let rl;
function ask(question, defaultVal = '') {
  const hint = defaultVal ? ` [${c.grey}${defaultVal}${c.reset}]` : '';
  return new Promise(resolve =>
    rl.question(`  ${question}${hint}: `, ans => resolve(ans.trim() || defaultVal))
  );
}

function hasGit() {
  try { execSync('git --version', { stdio: 'ignore' }); return true; }
  catch { return false; }
}

function cloneRepo(url, targetDir) {
  return spawnSync('git', ['clone', url, targetDir], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  }).status === 0;
}

function pullRepo(targetDir) {
  return spawnSync('git', ['-C', targetDir, 'pull', '--ff-only'], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  }).status === 0;
}

function injectToken(url, token) {
  return token ? url.replace('https://', `https://${token}@`) : url;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  title('SCE — Ecosystem Setup');
  hr();
  console.log('This script clones all SCE repositories into a single parent folder.');
  console.log('If a repository already exists it will be updated (git pull).\n');

  if (!hasGit()) {
    err('git is not installed or not in PATH. Please install git first.');
    process.exit(1);
  }

  rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  // ── Parent folder ─────────────────────────────────────────────────────────
  const folderInput = await ask('Parent folder name', 'SCE-ECOSYSTEM');
  const parentFolder = path.resolve(folderInput);
  console.log(`\nRepositories will be cloned into: ${c.bold}${parentFolder}${c.reset}\n`);

  // ── GitHub token ──────────────────────────────────────────────────────────
  const token = await ask('GitHub Personal Access Token (leave blank if repos are public)');

  // ── Select repos + allow URL override ────────────────────────────────────
  title('Select repositories to clone');
  hr();
  console.log('Press Enter to accept Yes. Type N to skip.');
  console.log('If the default URL is wrong, type C to enter a custom URL.\n');

  const selected = [];
  for (const repo of REPOS) {
    const ans = await ask(`Clone ${c.bold}${repo.label}${c.reset}? [Y/n/c]`);
    if (ans.toLowerCase() === 'n') continue;

    let finalUrl = repo.url;
    if (ans.toLowerCase() === 'c') {
      const custom = await ask(`  Custom URL for ${repo.key}`, repo.url);
      if (custom) finalUrl = custom;
    }

    selected.push({ ...repo, url: finalUrl });
  }

  if (selected.length === 0) {
    warn('No repositories selected. Exiting.');
    rl.close();
    return;
  }

  // ── Create parent folder ──────────────────────────────────────────────────
  if (!fs.existsSync(parentFolder)) {
    fs.mkdirSync(parentFolder, { recursive: true });
    ok(`Created folder: ${parentFolder}`);
  } else {
    dim(`Folder already exists: ${parentFolder}`);
  }

  // ── Clone / pull each repo ────────────────────────────────────────────────
  title('Cloning repositories');
  hr();

  const results = [];

  for (const repo of selected) {
    const targetDir = path.join(parentFolder, repo.folder);
    console.log(`\n${c.bold}→ ${repo.key}${c.reset}`);
    dim(repo.url);
    dim(`→ ${targetDir}`);

    // Already cloned — pull
    if (fs.existsSync(path.join(targetDir, '.git'))) {
      warn('Already cloned — running git pull...');
      if (pullRepo(targetDir)) {
        ok('Updated');
        results.push({ key: repo.key, action: 'pull', success: true });
      } else {
        err('git pull failed.');
        const retry = await ask('  Enter correct URL to re-clone, or leave blank to skip');
        if (retry) {
          const retryUrl = injectToken(retry, token);
          // Remove broken dir and re-clone
          fs.rmSync(targetDir, { recursive: true, force: true });
          if (cloneRepo(retryUrl, targetDir)) {
            ok('Cloned from new URL');
            results.push({ key: repo.key, action: 'clone', success: true });
          } else {
            err(`Clone failed again for ${repo.key}`);
            results.push({ key: repo.key, action: 'clone', success: false });
          }
        } else {
          results.push({ key: repo.key, action: 'pull', success: false });
        }
      }
      continue;
    }

    // Fresh clone
    const cloneUrl = injectToken(repo.url, token);
    if (cloneRepo(cloneUrl, targetDir)) {
      ok('Cloned');
      results.push({ key: repo.key, action: 'clone', success: true });
    } else {
      err(`git clone failed for ${repo.key}`);
      const retry = await ask('  Enter correct URL to try again, or leave blank to skip');
      if (retry) {
        const retryUrl = injectToken(retry, token);
        if (cloneRepo(retryUrl, targetDir)) {
          ok('Cloned from new URL');
          results.push({ key: repo.key, action: 'clone', success: true });
        } else {
          err(`Clone failed again for ${repo.key}`);
          results.push({ key: repo.key, action: 'clone', success: false });
        }
      } else {
        results.push({ key: repo.key, action: 'clone', success: false });
      }
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  title('Summary');
  hr();

  let allOk = true;
  for (const r of results) {
    if (r.success) ok(`${r.key} — ${r.action} succeeded`);
    else { err(`${r.key} — ${r.action} FAILED`); allOk = false; }
  }

  console.log();
  if (allOk) {
    log(`All done! Your ecosystem is in: ${c.bold}${parentFolder}${c.reset}`);
    console.log(`\n${c.grey}Next steps:${c.reset}`);
    console.log(`  1. cd ${parentFolder}`);
    console.log(`  2. Read SCE-Installation/README.md for full setup instructions`);
    console.log(`  3. Run: node SCE-Installation/docker-setup/configure.js\n`);
  } else {
    warn('Some repositories failed. Check the errors above and re-run the script.');
    process.exit(1);
  }

  rl.close();
}

main().catch(e => {
  err(`Unexpected error: ${e.message}`);
  if (rl) rl.close();
  process.exit(1);
});
