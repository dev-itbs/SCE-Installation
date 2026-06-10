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
const log   = (msg)       => console.log(`${c.cyan}${msg}${c.reset}`);
const ok    = (msg)       => console.log(`${c.green}  ✔ ${msg}${c.reset}`);
const warn  = (msg)       => console.log(`${c.yellow}  ⚠ ${msg}${c.reset}`);
const err   = (msg)       => console.log(`${c.red}  ✖ ${msg}${c.reset}`);
const dim   = (msg)       => console.log(`${c.grey}    ${msg}${c.reset}`);
const title = (msg)       => console.log(`\n${c.bold}${c.cyan}${msg}${c.reset}`);
const hr    = ()          => console.log(`${c.grey}${'─'.repeat(60)}${c.reset}`);

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

// ─── Helpers ─────────────────────────────────────────────────────────────────
function ask(rl, question) {
  return new Promise(resolve => rl.question(question, answer => resolve(answer.trim())));
}

function hasGit() {
  try {
    execSync('git --version', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function clone(repo, targetDir) {
  const result = spawnSync('git', ['clone', repo.url, targetDir], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  return result.status === 0;
}

function pull(targetDir) {
  const result = spawnSync('git', ['-C', targetDir, 'pull', '--ff-only'], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  return result.status === 0;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  title('SCE — Ecosystem Setup');
  hr();
  console.log('This script clones all SCE repositories into a single parent folder.');
  console.log('If a repository already exists it will be updated (git pull).\n');

  // Pre-flight check
  if (!hasGit()) {
    err('git is not installed or not in PATH. Please install git first.');
    process.exit(1);
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  // ── Ask for parent folder ──────────────────────────────────────────────────
  const defaultFolder = 'SCE-ECOSYSTEM';
  const folderInput = await ask(
    rl,
    `${c.bold}Parent folder name${c.reset} [${c.cyan}${defaultFolder}${c.reset}]: `
  );
  const parentFolder = path.resolve(folderInput || defaultFolder);

  console.log(`\nRepositories will be cloned into: ${c.bold}${parentFolder}${c.reset}\n`);

  // ── Ask which repos to clone ───────────────────────────────────────────────
  title('Select repositories to clone');
  hr();
  console.log('Press Enter to accept default (Y). Answer N to skip a repository.\n');

  const selected = [];
  for (const repo of REPOS) {
    const answer = await ask(rl, `  Clone ${c.bold}${repo.label}${c.reset}? [Y/n]: `);
    if (answer.toLowerCase() !== 'n') {
      selected.push(repo);
    }
  }

  if (selected.length === 0) {
    warn('No repositories selected. Exiting.');
    rl.close();
    return;
  }

  // ── Optional: ask for a GitHub token (for private repos) ──────────────────
  console.log();
  const tokenInput = await ask(
    rl,
    `${c.bold}GitHub Personal Access Token${c.reset} (leave blank if repos are public): `
  );
  const token = tokenInput.trim();

  rl.close();

  // ── Create parent folder ───────────────────────────────────────────────────
  if (!fs.existsSync(parentFolder)) {
    fs.mkdirSync(parentFolder, { recursive: true });
    ok(`Created folder: ${parentFolder}`);
  } else {
    dim(`Folder already exists: ${parentFolder}`);
  }

  // ── Clone / pull each repo ─────────────────────────────────────────────────
  title('Cloning repositories');
  hr();

  const results = [];

  for (const repo of selected) {
    const targetDir = path.join(parentFolder, repo.folder);
    const repoWithAuth = token
      ? repo.url.replace('https://', `https://${token}@`)
      : repo.url;

    console.log(`\n${c.bold}→ ${repo.key}${c.reset}`);
    dim(`  ${repo.url}`);
    dim(`  → ${targetDir}`);

    if (fs.existsSync(path.join(targetDir, '.git'))) {
      warn('Already cloned — running git pull...');
      const success = pull(targetDir);
      results.push({ repo: repo.key, action: 'pull', success });
    } else {
      const repoToClone = { ...repo, url: repoWithAuth };
      const success = clone(repoToClone, targetDir);
      results.push({ repo: repo.key, action: 'clone', success });
    }
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  title('Summary');
  hr();

  let allOk = true;
  for (const r of results) {
    if (r.success) {
      ok(`${r.repo} — ${r.action} succeeded`);
    } else {
      err(`${r.repo} — ${r.action} FAILED`);
      allOk = false;
    }
  }

  console.log();

  if (allOk) {
    log(`All done! Your ecosystem is in: ${c.bold}${parentFolder}${c.reset}`);
    console.log(`\n${c.grey}Next steps:${c.reset}`);
    console.log(`  1. cd ${parentFolder}`);
    console.log(`  2. Read SCE-Installation/README.md for full setup instructions`);
    console.log(`  3. Start with VaultFlow360, then SCE-Installation/prerequisite, then the apps.\n`);
  } else {
    warn('Some repositories failed. Check the errors above and re-run the script.');
    process.exit(1);
  }
}

main().catch(e => {
  err(`Unexpected error: ${e.message}`);
  process.exit(1);
});
