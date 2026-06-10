#!/usr/bin/env node
/**
 * SCE Ecosystem — Docker Environment Configurator
 *
 * Scans sibling folders, asks for credentials once, then writes all .env
 * files and starts Docker stacks in the correct order.
 *
 * Usage:
 *   node configure.js
 */

'use strict';

const { execSync, spawnSync } = require('child_process');
const readline = require('readline');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// ── Colour helpers ────────────────────────────────────────────────────────────
const c = {
  reset: '\x1b[0m', bold: '\x1b[1m',
  cyan: '\x1b[36m', green: '\x1b[32m',
  yellow: '\x1b[33m', red: '\x1b[31m', grey: '\x1b[90m', blue: '\x1b[34m',
};
const log   = m => console.log(`${c.cyan}${m}${c.reset}`);
const ok    = m => console.log(`${c.green}  ✔ ${m}${c.reset}`);
const warn  = m => console.log(`${c.yellow}  ⚠ ${m}${c.reset}`);
const info  = m => console.log(`${c.blue}  ℹ ${m}${c.reset}`);
const err   = m => console.log(`${c.red}  ✖ ${m}${c.reset}`);
const dim   = m => console.log(`${c.grey}    ${m}${c.reset}`);
const title = m => console.log(`\n${c.bold}${c.cyan}━━━  ${m}  ━━━${c.reset}\n`);
const hr    = () => console.log(`${c.grey}${'─'.repeat(70)}${c.reset}`);

// ── Prompt helper ─────────────────────────────────────────────────────────────
let rl;
function ask(question, defaultVal = '') {
  const hint = defaultVal ? ` [${c.grey}${defaultVal}${c.reset}]` : '';
  return new Promise(resolve => {
    rl.question(`  ${question}${hint}: `, ans => {
      const v = ans.trim();
      resolve(v === '' ? defaultVal : v);
    });
  });
}
async function askRequired(question) {
  let v = '';
  while (!v) {
    v = (await ask(`${question} ${c.red}(required)${c.reset}`)).trim();
    if (!v) warn('This field is required.');
  }
  return v;
}
async function askYN(question, defaultYes = true) {
  const hint = defaultYes ? '[Y/n]' : '[y/N]';
  const ans = await ask(`${question} ${hint}`);
  if (!ans) return defaultYes;
  return ans.toLowerCase().startsWith('y');
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function randSecret(bytes = 32) {
  return crypto.randomBytes(bytes).toString('hex');
}
function slugify(str) {
  return str.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
function writeEnv(filePath, lines) {
  fs.writeFileSync(filePath, lines.join('\n') + '\n', 'utf8');
  ok(`Written: ${path.relative(ROOT, filePath)}`);
}
function run(cmd, cwd) {
  return spawnSync(cmd, { stdio: 'inherit', shell: true, cwd });
}
function dockerUp(cwd, envFile) {
  const envFlag = envFile ? `--env-file ${envFile}` : '';
  return run(`docker compose ${envFlag} up -d --build`, cwd);
}

// ── Discover ecosystem root & repo folders ────────────────────────────────────
// This script lives in  <ECOSYSTEM>/SCE-Installation/docker-setup/configure.js
// So ROOT = two levels up.
const ROOT = path.resolve(__dirname, '..', '..');

function discoverRepos() {
  const repos = {};
  const KNOWN = {
    vault:    ['VaultFlow360'],
    prereq:   ['SCE-Installation'],
    php:      ['SCE-PHP-SYSTEMS'],
    python:   ['SCE-Python-Service'],
    cpa:      ['SCE-Vue-CPA'],
    eassist:  ['eAssist-AI-Service'],
  };
  const entries = fs.readdirSync(ROOT, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .map(e => e.name);

  for (const [key, candidates] of Object.entries(KNOWN)) {
    for (const name of entries) {
      if (candidates.some(c => name.toLowerCase().includes(c.toLowerCase()))) {
        repos[key] = path.join(ROOT, name);
        repos[`${key}Name`] = name;
        break;
      }
    }
    // Fallback: fuzzy match on key substring
    if (!repos[key]) {
      for (const name of entries) {
        if (name.toLowerCase().includes(key.toLowerCase())) {
          repos[key] = path.join(ROOT, name);
          repos[`${key}Name`] = name;
          break;
        }
      }
    }
  }
  return repos;
}

async function resolveRepos(repos) {
  const LABELS = {
    vault:   'VaultFlow360        (PostgreSQL HA)',
    prereq:  'SCE-Installation    (This installer repo)',
    php:     'SCE-PHP-SYSTEMS     (PHP web app)',
    python:  'SCE-Python-Service  (FastAPI + workers)',
    cpa:     'SCE-Vue-CPA         (Citizen Portal App)',
    eassist: 'eAssist-AI-Service  (AI assistant)',
  };
  for (const [key, label] of Object.entries(LABELS)) {
    if (repos[key]) {
      ok(`Found ${label} → ${path.relative(ROOT, repos[key])}`);
    } else {
      warn(`Could not find ${label}`);
      const ans = await ask(`  Enter folder name inside ${ROOT} (or leave blank to skip)`);
      if (ans) {
        const full = path.isAbsolute(ans) ? ans : path.join(ROOT, ans);
        if (fs.existsSync(full)) {
          repos[key] = full;
          repos[`${key}Name`] = path.basename(full);
          ok(`Using ${full}`);
        } else {
          warn(`Path not found: ${full} — skipping ${label}`);
        }
      } else {
        dim(`Skipping ${label}`);
      }
    }
  }
  return repos;
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  console.clear();
  console.log(`${c.bold}${c.cyan}`);
  console.log('  ╔═══════════════════════════════════════════════════════╗');
  console.log('  ║       SCE Ecosystem — Docker Environment Setup        ║');
  console.log('  ╚═══════════════════════════════════════════════════════╝');
  console.log(c.reset);
  console.log(`  Ecosystem root: ${c.bold}${ROOT}${c.reset}\n`);

  // ── Discover repos ─────────────────────────────────────────────────────────
  const ecosystemName = path.basename(ROOT);
  log('Scanning for repositories...\n');
  const repos = await resolveRepos(discoverRepos());
  console.log();

  // ── Check if env already configured ───────────────────────────────────────
  hr();
  const alreadyConfigured = await askYN(
    'Have you already configured the .env files and just want to (re)start Docker?',
    false
  );

  if (alreadyConfigured) {
    console.log();
    warn('Skipping env generation. Only updating folder paths and Docker-to-Docker URLs.');
    await patchDockerUrls(repos, ecosystemName);
    await startDockerStacks(repos);
    rl.close();
    return;
  }

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 1 — Deployment Type');
  // ══════════════════════════════════════════════════════════════════════════
  const isOnPrem = await askYN(
    'Is this an ON-PREM deployment? (MinIO instead of cloud S3)',
    false
  );
  console.log();

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 2 — Domain & Identity');
  // ══════════════════════════════════════════════════════════════════════════
  info('Enter your public domain, or press Enter to use localhost for local development.');
  const domain = await ask('System domain (no https://, no trailing slash)', 'localhost');
  const isLocalhost = domain === 'localhost' || domain.startsWith('localhost:');
  const domainUrl = isLocalhost ? `http://${domain}` : `https://${domain}`;

  info('LGU short code used for internal identifiers (e.g. mabalacat)');
  const lguCode = await ask('LGU code', slugify(ecosystemName));
  const lguName = await ask('LGU full name', ecosystemName.replace(/-/g, ' '));

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 3 — Database (VaultFlow360 / PostgreSQL)');
  // ══════════════════════════════════════════════════════════════════════════
  const pgDb       = await ask('PostgreSQL database name', 'postgres');
  const pgUser     = await ask('PostgreSQL app username', 'appuser');
  const pgPassword = await ask('PostgreSQL app password', randSecret(16));
  const pgSuperPw  = await ask('PostgreSQL superuser password', randSecret(16));
  const repmgrPw   = await ask('Repmgr password', randSecret(16));
  const pgpoolUser = await ask('Pgpool admin username', 'admin');
  const pgpoolPw   = await ask('Pgpool admin password', randSecret(16));
  const backupPw   = await ask('Backup API admin password', randSecret(16));
  const backupKey  = await ask('Backup API key', randSecret(12));

  info('External Postgres host for Pgpool replication (leave blank if none)');
  const pgExtHost  = await ask('PGPOOL_EXTERNAL_PG_HOST', '');
  const pgExtPort  = pgExtHost ? await ask('PGPOOL_EXTERNAL_PG_PORT', '5432') : '';

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 4 — Redis & EMQX');
  // ══════════════════════════════════════════════════════════════════════════
  const redisPassword  = await ask('Redis password', randSecret(16));
  const emqxDashPw     = await ask('EMQX dashboard password', randSecret(16));
  info('EMQX API key and secret are created in the EMQX dashboard AFTER first boot.');
  info('Leave blank now — you will fill them in later.');
  const mqApiKey    = await ask('EMQX API key (optional, fill after boot)', '');
  const mqApiSecret = await ask('EMQX API secret (optional, fill after boot)', '');
  const mqTopic     = await ask('MQTT topic', lguCode);

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 5 — S3 / Object Storage');
  // ══════════════════════════════════════════════════════════════════════════
  let s3Endpoint, s3Bucket, s3Region, s3Key, s3Secret, s3ForcePathStyle;
  if (isOnPrem) {
    info('On-prem: MinIO will be used. Container hostname is sce-minio.');
    s3Endpoint       = 'http://sce-minio:9000';
    s3Bucket         = await ask('MinIO bucket name', lguCode);
    s3Region         = 'us-east-1';
    s3Key            = await ask('MinIO access key', 'minioadmin');
    s3Secret         = await ask('MinIO secret key', randSecret(16));
    s3ForcePathStyle = 'true';
    info(`Remember to create the bucket "${s3Bucket}" in MinIO console after first boot.`);
  } else {
    info('Cloud: provide your S3-compatible storage credentials.');
    s3Endpoint       = await ask('S3 endpoint URL (e.g. https://sgp1.digitaloceanspaces.com)');
    s3Bucket         = await ask('S3 bucket name');
    s3Region         = await ask('S3 region', 'sgp1');
    s3Key            = await ask('S3 access key');
    s3Secret         = await ask('S3 secret key');
    s3ForcePathStyle = 'false';
  }
  const s3UploadPath    = await ask(`S3 prefix for uploads`, `${ecosystemName}/uploads/`);
  const emsFilePath     = await ask(`S3 prefix for EMS incident files`, `${ecosystemName}/incident/`);
  const uploadDestPath  = await ask(`S3 prefix for final uploads`, `${ecosystemName}/dest/`);

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 6 — PHP App Settings (SCE-PHP-SYSTEMS)');
  // ══════════════════════════════════════════════════════════════════════════
  const hashSalt       = await ask('HASH_ID_SALT (random string)', randSecret(16));
  const partnerIdVal   = await ask('PARTNER_ID', lguCode);
  const faceCollection = await ask('AWS Rekognition FACE_COLLECTION name (create after install)');
  const googleMapsId   = await ask('EMS Google Maps Map ID');
  const emsLevel       = await ask('EMS dispatch level', '1');
  const emsBoundaryKm  = await ask('EMS boundary radius (km)', '10');

  info(`Cookie domain = the domain where browsers send auth cookies.`);
  const cookieDomain   = await ask('COOKIE_DOMAIN', domain);

  info('Mailgun is used for email notifications.');
  const mailgunDomain  = await ask('Mailgun domain');
  const mailgunApiKey  = await ask('Mailgun API key');
  const mailgunValKey  = await ask('Mailgun validation key');

  info('Firebase — used for push notifications (Android/iOS).');
  const firebaseVapid  = await ask('FIREBASE_VAPID_KEY');
  const fcmEndpoint    = await ask('FCM_ENDPOINT');
  const serviceAccPath = await ask('SERVICE_ACCOUNT_PATH (path inside container to JSON)', '/var/www/sce/firebase-service-account.json');
  const apnsKeyId      = await ask('APNS_KEY_ID');
  const apnsTeamId     = await ask('APNS_TEAM_ID');
  const bundleId       = await ask('BUNDLE_ID (iOS app bundle ID)');
  const keypath        = await ask('KEYPATH (path to .p8 APNs key inside container)', '/var/www/sce/apns.p8');

  info('ICE_SERVERS — JSON array of STUN/TURN servers for WebRTC.');
  info('Example: [{"urls":["stun:stun.l.google.com:19302"]}]');
  const iceServers     = await ask('ICE_SERVERS', '[{"urls":["stun:stun.l.google.com:19302"]}]');

  const cctvEnabled    = await askYN('Enable CCTV integration?', false);

  info('eAssist plugin path served by the PHP container.');
  const eassistPlugin  = await ask('EASSIST_PLUGIN (URL path to dist-plugin)', `${domainUrl}/eassist/dist-plugin`);

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 7 — Python Service Settings');
  // ══════════════════════════════════════════════════════════════════════════
  const jwtSecret      = await ask('JWT_SECRET_KEY', randSecret(32));
  const openaiKey      = await ask('OpenAI API key');
  const openaiModel    = await ask('OpenAI model', 'gpt-4o-mini');
  const faceThreshold  = await ask('FACE_MATCH_THRESHOLD (0.0-1.0)', '0.45');

  let vssHost = '', vssUser = '', vssPw = '', vssStompPort = '', isTailscale = 'false', tailscaleIp = '';
  let cctvCompose = '';
  if (cctvEnabled) {
    info('VSS (Video Surveillance System) connection details.');
    vssHost      = await ask('VSS_IP_PORT (host:port or hostname)');
    vssUser      = await ask('VSS_USERNAME', 'system');
    vssPw        = await ask('VSS_PASSWORD');
    vssStompPort = await ask('VSS_STOMP_PORT', '61615');
    isTailscale  = await askYN('Using Tailscale VPN?', false) ? 'true' : 'false';
    if (isTailscale === 'true') tailscaleIp = await ask('Tailscale IP of this host');
    cctvCompose  = 'cctv';
  }

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 8 — eAssist AI Service');
  // ══════════════════════════════════════════════════════════════════════════
  info('OpenAI key for eAssist (can reuse the same key from Step 7).');
  const eassistOaiKey  = await ask('OpenAI API key for eAssist', openaiKey);
  const eassistModel   = await ask('LLM model for eAssist', 'gpt-4o-mini');

  // ══════════════════════════════════════════════════════════════════════════
  // WRITE ALL .ENV FILES
  // ══════════════════════════════════════════════════════════════════════════
  title('Writing .env files');

  // ── Convenience: resolve container paths based on repo location ───────────
  const phpDir    = repos.php    || path.join(ROOT, 'SCE-PHP-SYSTEMS');
  const pythonDir = repos.python || path.join(ROOT, 'SCE-Python-Service');
  const vaultDir  = repos.vault  || path.join(ROOT, 'VaultFlow360');
  const prereqDir = repos.prereq ? path.join(repos.prereq, 'prerequisite') : path.join(ROOT, 'SCE-Installation', 'prerequisite');
  const eassistDir = repos.eassist || path.join(ROOT, 'eAssist-AI-Service');

  // ─────────────────────────────────────────────────────────────────────────
  // 1. VaultFlow360 / postgres-wal.env
  // ─────────────────────────────────────────────────────────────────────────
  if (fs.existsSync(vaultDir)) {
    const backupDbPath = path.join(vaultDir, 'backups', 'data', 'backup-api.db').replace(/\\/g, '/');
    const pgExtLine    = pgExtHost
      ? `PGPOOL_EXTERNAL_PG_HOST=${pgExtHost}\nPGPOOL_EXTERNAL_PG_PORT=${pgExtPort}`
      : `PGPOOL_EXTERNAL_PG_HOST=\nPGPOOL_EXTERNAL_PG_PORT=5432`;
    const s3VaultEndpoint = isOnPrem ? 'http://sce-minio:9000' : s3Endpoint;

    writeEnv(path.join(vaultDir, 'postgres-wal.env'), [
      '# Generated by SCE configure.js',
      `POSTGRES_DB=${pgDb}`,
      `POSTGRES_USER=${pgUser}`,
      `POSTGRES_PASSWORD=${pgPassword}`,
      `POSTGRES_SUPERUSER_PASSWORD=${pgSuperPw}`,
      `REPMGR_PASSWORD=${repmgrPw}`,
      `PGPOOL_ADMIN_USERNAME=${pgpoolUser}`,
      `PGPOOL_ADMIN_PASSWORD=${pgpoolPw}`,
      `POSTGRES_HOST_PORT=55432`,
      `POSTGRES_EXPORTER_HOST_PORT=9187`,
      '',
      '# Backup API',
      `BACKUP_API_HOST_PORT=8090`,
      `BACKUP_API_PORT=8080`,
      `BACKUP_API_KEY=${backupKey}`,
      `PITR_RESTORE_HOST_PORT=55433`,
      `BACKUP_ADMIN_USERNAME=admin`,
      `BACKUP_ADMIN_PASSWORD=${backupPw}`,
      `BACKUP_API_DB_PATH=${backupDbPath}`,
      `BACKUP_SESSION_TTL_HOURS=24`,
      `BACKUP_COOKIE_SECURE=false`,
      `BACKUP_SCHEDULE_ENABLED=true`,
      `BACKUP_DAILY_TIME=02:00`,
      `BACKUP_TIMEZONE=Asia/Manila`,
      `BACKUP_RETENTION_COUNT=7`,
      `BACKUP_TIMEOUT_MINUTES=120`,
      `BACKUP_WAL_UPLOAD_ENABLED=true`,
      `BACKUP_WAL_UPLOAD_INTERVAL_SECONDS=60`,
      `BACKUP_WAL_UPLOAD_BATCH_SIZE=10`,
      `BACKUP_WAL_UPLOAD_FORCE_SWITCH=false`,
      `BACKUP_POSTGRES_HOST=pg-0`,
      pgExtLine,
      `BACKUP_POSTGRES_PORT=5432`,
      `BACKUP_LOCAL_DIR=/backups`,
      `BACKUP_WAL_DIR=/wal-archive`,
      '',
      '# S3 backup storage',
      `BACKUP_S3_ENABLED=${isOnPrem ? 'true' : 'false'}`,
      `BACKUP_S3_ENDPOINT=${s3VaultEndpoint}`,
      `BACKUP_S3_REGION=${s3Region}`,
      `BACKUP_S3_BUCKET=${s3Bucket}`,
      `BACKUP_S3_PREFIX=${ecosystemName}-pg-backup`,
      `BACKUP_S3_ACCESS_KEY_ID=${s3Key}`,
      `BACKUP_S3_SECRET_ACCESS_KEY=${s3Secret}`,
      `BACKUP_S3_FORCE_PATH_STYLE=${s3ForcePathStyle}`,
      '',
      'OBJECT_BACKUP_ENABLED=false',
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. SCE-Installation/prerequisite/.env
  // ─────────────────────────────────────────────────────────────────────────
  if (fs.existsSync(prereqDir)) {
    writeEnv(path.join(prereqDir, '.env'), [
      '# Generated by SCE configure.js',
      `REDIS_VERSION=7-alpine`,
      `REDIS_PORT=6379`,
      `REDIS_PASSWORD=${redisPassword}`,
      '',
      `EMQX_VERSION=5.0.26`,
      `EMQX_MQTT_PORT=1883`,
      `EMQX_WS_PORT=8083`,
      `EMQX_WSS_PORT=2096`,
      `EMQX_MQTTS_PORT=8883`,
      `EMQX_DASHBOARD_PORT=18083`,
      `EMQX_DASHBOARD_USER=admin`,
      `EMQX_DASHBOARD_PASSWORD=${emqxDashPw}`,
      '',
      `COMPOSE_PROFILES=${isOnPrem ? 'onprem' : ''}`,
      `MINIO_VERSION=latest`,
      `MINIO_API_PORT=9010`,
      `MINIO_CONSOLE_PORT=9011`,
      `MINIO_ACCESS_KEY=${s3Key}`,
      `MINIO_SECRET_KEY=${s3Secret}`,
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. SCE-PHP-SYSTEMS/.env
  // ─────────────────────────────────────────────────────────────────────────
  if (fs.existsSync(phpDir)) {
    const phpEnvPath = path.join(phpDir, '.env');
    // Container paths (always Linux inside Docker)
    const uploadTempPath = '/var/www/sce/temp_uploads/';
    const uploadTempHref = `${domainUrl}/temp_uploads/`;
    const s3PhpEndpoint  = isOnPrem ? 'http://sce-minio:9000' : s3Endpoint;

    writeEnv(phpEnvPath, [
      '# Generated by SCE configure.js',
      '',
      '# Database',
      `DB_HOST=postgres-wal-pgpool`,
      `DB_PORT=5432`,
      `DB_NAME=${pgDb}`,
      `DB_USER=${pgUser}`,
      `DB_PASSWORD=${pgPassword}`,
      '',
      '# Redis',
      `REDIS_HOST=sce-redis`,
      `REDIS_PORT=6379`,
      `REDIS_PASSWORD=${redisPassword}`,
      `REDIS_DB=0`,
      `REDIS_PREFIX=`,
      '',
      '# S3',
      `S3_ENDPOINT=${s3PhpEndpoint}`,
      `S3_BUCKET=${s3Bucket}`,
      `S3_REGION=${s3Region}`,
      `S3_KEY=${s3Key}`,
      `S3_SECRET=${s3Secret}`,
      `S3_UPLOAD_PATH=${s3UploadPath}`,
      '',
      '# Mailgun',
      `MAILGUN_DOMAIN=${mailgunDomain}`,
      `MAILGUN_API_KEY=${mailgunApiKey}`,
      `MAILGUN_VALIDATION_KEY=${mailgunValKey}`,
      '',
      '# Cookies',
      `COOKIE_NAME_PREFIX=auth_`,
      `COOKIE_PATH=/`,
      `COOKIE_DOMAIN=${cookieDomain}`,
      `COOKIE_SECURE=true`,
      `COOKIE_HTTPONLY=true`,
      `COOKIE_SAMESITE=None`,
      '',
      '# EMQX / MQTT',
      `MQ_API_URL=http://sce-emqx:18083`,
      `MQ_API_KEY=${mqApiKey}`,
      `MQ_API_SECRET=${mqApiSecret}`,
      `MQ_WS_URL=ws://sce-emqx:8083/mqtt`,
      `MQ_TOPIC=${mqTopic}`,
      '',
      '# System identity',
      `LGU=${lguCode}`,
      `LGU_NAME=${lguName}`,
      `HASH_ID_SALT=${hashSalt}`,
      `PARTNER_ID=${partnerIdVal}`,
      '',
      '# Upload paths',
      `UPLOAD_TEMP_PATH=${uploadTempPath}`,
      `UPLOAD_TEMP_HREF_PATH=${uploadTempHref}`,
      `UPLOAD_DEST_PATH=${uploadDestPath}`,
      '',
      '# URLs',
      `QRCODE_BASE_URL=${domainUrl}/CPA/#/deeplink?data=`,
      `CPA_DOWNLOAD_URL=${domainUrl}/CPA/download`,
      `CPA_LOGIN_URL=${domainUrl}/CPA/#/login`,
      `PYTHON_API_URL=http://sce-python-api:8000`,
      `SCE_SETTINGS_API_URL=${domainUrl}/UAC/api`,
      '',
      '# Face / KYC',
      `FACE_COLLECTION=${faceCollection}`,
      '',
      '# EMS',
      `EMS_APP_NAME=EMS`,
      `EMS_GOOGLE_MAPS_MAP_ID=${googleMapsId}`,
      `EMS_FILE_PATH=${emsFilePath}`,
      `EMS_SYSTEM_BASE_URL=/EMS`,
      `EMS_LEVEL=${emsLevel}`,
      `EMS_BOUNDARY_KM=${emsBoundaryKm}`,
      '',
      '# Firebase / Push notifications',
      `FCM_ENDPOINT=${fcmEndpoint}`,
      `SERVICE_ACCOUNT_PATH=${serviceAccPath}`,
      `APNS_KEY_ID=${apnsKeyId}`,
      `APNS_TEAM_ID=${apnsTeamId}`,
      `BUNDLE_ID=${bundleId}`,
      `KEYPATH=${keypath}`,
      `FIREBASE_VAPID_KEY=${firebaseVapid}`,
      '',
      '# WebRTC',
      `ICE_SERVERS=${iceServers}`,
      '',
      '# CCTV / AI',
      `CCTV_INTEGRATION_SERVICE=${cctvEnabled ? 'true' : 'false'}`,
      `EASSIST_PLUGIN=${eassistPlugin}`,
      '',
      '# BullMQ',
      `BULLMQ_EXPORT_QUEUE=export_records`,
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. SCE-Python-Service/.env
  // ─────────────────────────────────────────────────────────────────────────
  if (fs.existsSync(pythonDir)) {
    const streamsDir = '/app/streams';
    const uploadsDir = '/tmp/imports';
    const s3PyEndpoint = isOnPrem ? 'http://sce-minio:9000' : s3Endpoint;

    writeEnv(path.join(pythonDir, '.env'), [
      '# Generated by SCE configure.js',
      '',
      '# Database',
      `UAC_DB_URL=postgresql://${pgUser}:${pgPassword}@postgres-wal-pgpool:5432/${pgDb}`,
      `IMPORT_DB_URL=postgresql://${pgUser}:${pgPassword}@postgres-wal-pgpool:5432/${pgDb}`,
      '',
      '# S3',
      `S3_ENDPOINT_URL=${s3PyEndpoint}`,
      `S3_ACCESS_KEY=${s3Key}`,
      `S3_SECRET_KEY=${s3Secret}`,
      `S3_BUCKET_NAME=${s3Bucket}`,
      `S3_REGION=${s3Region}`,
      `S3_PREFIX=${ecosystemName}`,
      '',
      '# Callback to PHP',
      `PHP_CALLBACK_TIMEOUT=30`,
      `PHP_CALLBACK_MAX_RETRIES=3`,
      `PHP_CALLBACK_RETRY_DELAY=5`,
      '',
      '# Temp dirs (container paths)',
      `TMP_DIR=/tmp/pnpki-signer`,
      `UPLOAD_PATH=${uploadsDir}`,
      '',
      '# Redis',
      `REDIS_HOST=sce-redis`,
      `REDIS_PORT=6379`,
      `REDIS_DB=0`,
      `REDIS_PASSWORD=${redisPassword}`,
      `CACHE_EXPIRE_IN_SECONDS=300`,
      '',
      '# JWT',
      `JWT_SECRET_KEY=${jwtSecret}`,
      `JWT_ALGORITHM=HS512`,
      `TOKEN_ISSUER=${domain}`,
      `ACCESS_TOKEN_EXPIRE_MINUTES=43200`,
      '',
      '# BullMQ',
      `BULLMQ_FACE_VERIFICATION_QUEUE=kyc_face_verification`,
      `BULLMQ_DOCUMENT_QUEUE=document_processing`,
      `BULLMQ_EXPORT_QUEUE=export_tasks`,
      `BULLMQ_ATTEMPTS=3`,
      `BULLMQ_BACKOFF_TYPE=exponential`,
      `BULLMQ_BACKOFF_DELAY=5000`,
      `BULLMQ_REMOVE_ON_COMPLETE=100`,
      `BULLMQ_REMOVE_ON_FAIL=100`,
      '',
      '# AI — OpenAI',
      `AI_PROVIDER=openai`,
      `OPENAI_API_KEY=${openaiKey}`,
      `OPENAI_MODEL_NAME=${openaiModel}`,
      `GEMINI_API_KEY=`,
      `GEMINI_MODEL_NAME=gemini-2.0-flash`,
      '',
      '# Face verification',
      `FACE_MATCH_THRESHOLD=${faceThreshold}`,
      `FACE_PRIMARY_MODEL=buffalo_l`,
      `KYC_NAME_SIMILARITY_THRESHOLD=0.8`,
      `KYC_ENABLE_STRICT_VALIDATION=true`,
      `KYC_REQUIRE_BOTH_SIDES=false`,
      '',
      '# EMQX',
      `EMQX_HOST=http://sce-emqx:18083`,
      `EMQX_PORT=2096`,
      `EMQX_KEY=${mqApiKey}`,
      `EMQX_SECRET=${mqApiSecret}`,
      `EMQX_TOPIC=${mqTopic}`,
      '',
      '# CCTV',
      `CCTV_SERVICE_ENABLED=${cctvEnabled ? 'true' : 'false'}`,
      `COMPOSE_PROFILES=${cctvCompose}`,
      `VSS_IP_PORT=${vssHost}`,
      `VSS_USERNAME=${vssUser}`,
      `VSS_PASSWORD=${vssPw}`,
      `VSS_STOMP_PORT=${vssStompPort}`,
      `VSS_SUBSCRIBE_TOPICS=mq.event.msg.topic,mq.alarm.msg.topic,mq.common.msg.topic`,
      `VSS_PRIVATE_KEY=`,
      `VSS_PUBLIC_KEY=`,
      '',
      '# Stream server',
      `HTTP_SERVER_HOST=http://sce-stream-server:8081`,
      `HTTP_SERVER_PORT=8081`,
      `STREAMS_DIR=${streamsDir}`,
      `STREAM_ACTIVE_THRESHOLD_S=30`,
      `STREAM_IDLE_TIMEOUT_S=300`,
      `IDLE_CHECK_INTERVAL_S=60`,
      '',
      '# CCTV worker queues',
      `TREE_QUEUE_NAME=cctv-device-tree`,
      `STATUS_QUEUE_NAME=cctv-device-status`,
      `CCTV_TREE_INTERVAL_MS=300000`,
      `CCTV_STATUS_INTERVAL_MS=300000`,
      `FAILURE_REQUEUE_DELAY_MS=300000`,
      `DEVICE_INFO_DELAY_S=0.5`,
      `STATUS_BATCH_SIZE=10`,
      `STATUS_BATCH_DELAY_S=0.3`,
      `VSS_REQUEST_TIMEOUT=60`,
      '',
      '# Network',
      `IS_TAILSCALE_CONNECT=${isTailscale}`,
      `TAILSCALE_IP=${tailscaleIp}`,
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. eAssist-AI-Service/.env
  // ─────────────────────────────────────────────────────────────────────────
  if (fs.existsSync(eassistDir)) {
    writeEnv(path.join(eassistDir, '.env'), [
      '# Generated by SCE configure.js',
      `OPENAI_API_KEY=${eassistOaiKey}`,
      `LLM_PROVIDER=openai`,
      `LM_STUDIO_URL=`,
      `LLM_MODEL=${eassistModel}`,
      `PORT=3002`,
      `HOST=0.0.0.0`,
      `NODE_ENV=production`,
      `APP_BASE_PATH=`,
      `COPILOTKIT_TELEMETRY_DISABLED=true`,
      '',
      `SCE_USERNAME=admin`,
      `SCE_PASSWORD=`,
      `SCE_APP_TYPE=ITBS`,
      '',
      `CRMS_DATA_SOURCE=api`,
      `CRMS_API_BASE_URL=http://sce-php-app/CRMS`,
      `CRMS_DEBUG=false`,
      '',
      `EMS_DATA_SOURCE=api`,
      `EMS_API_BASE_URL=http://sce-php-app/EMS`,
      `EMS_DEBUG=false`,
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  title('STEP 9 — Start Docker Stacks');
  // ══════════════════════════════════════════════════════════════════════════
  const startNow = await askYN('Start all Docker stacks now?', true);
  if (startNow) {
    await startDockerStacks(repos);
  } else {
    info('Skipped Docker start. Run the stacks manually in order:');
    printStartOrder(repos);
  }

  // ══════════════════════════════════════════════════════════════════════════
  title('DONE — Post-install checklist');
  // ══════════════════════════════════════════════════════════════════════════
  printPostInstallChecklist({
    domain, domainUrl, isOnPrem, s3Bucket, mqApiKey,
    faceCollection, cctvEnabled, repos,
  });

  rl.close();
}

// ── Patch only Docker URLs and folder paths (skip-config mode) ────────────────
async function patchDockerUrls(repos, ecosystemName) {
  warn('(Patch mode: only container hostnames and paths are updated in existing .env files)');
  // Minimal: just confirm paths look right
  ok('Paths based on Docker container names are already correct in generated .env files.');
}

// ── Start Docker stacks ───────────────────────────────────────────────────────
async function startDockerStacks(repos) {
  const steps = [
    { name: 'VaultFlow360 (PostgreSQL HA)', dir: repos.vault,  cmd: 'docker compose --env-file postgres-wal.env up -d --build' },
    { name: 'Prerequisites (Redis/EMQX/MinIO)', dir: repos.prereq ? path.join(repos.prereq, 'prerequisite') : null, cmd: 'docker compose up -d' },
    { name: 'SCE-PHP-SYSTEMS', dir: repos.php,    cmd: 'docker compose up -d --build' },
    { name: 'SCE-Python-Service', dir: repos.python, cmd: 'docker compose up -d --build' },
    { name: 'eAssist-AI-Service', dir: repos.eassist, cmd: 'docker compose up -d --build' },
  ];

  for (const step of steps) {
    if (!step.dir || !fs.existsSync(step.dir)) {
      warn(`Skipping ${step.name} — directory not found.`);
      continue;
    }
    log(`\nStarting: ${step.name}`);
    dim(`  cd ${step.dir}`);
    dim(`  ${step.cmd}`);
    const result = spawnSync(step.cmd, { stdio: 'inherit', shell: true, cwd: step.dir });
    if (result.status !== 0) {
      err(`Failed to start ${step.name}. Check errors above.`);
    } else {
      ok(`${step.name} started.`);
    }
    // Small pause between stacks so networks are ready
    await new Promise(r => setTimeout(r, 2000));
  }
}

function printStartOrder(repos) {
  console.log();
  if (repos.vault)    dim(`cd "${repos.vault}" && docker compose --env-file postgres-wal.env up -d --build`);
  if (repos.prereq)   dim(`cd "${path.join(repos.prereq,'prerequisite')}" && docker compose up -d`);
  if (repos.php)      dim(`cd "${repos.php}" && docker compose up -d --build`);
  if (repos.python)   dim(`cd "${repos.python}" && docker compose up -d --build`);
  if (repos.eassist)  dim(`cd "${repos.eassist}" && docker compose up -d --build`);
  console.log();
}

// ── Post-install checklist ────────────────────────────────────────────────────
function printPostInstallChecklist({ domain, domainUrl, isOnPrem, s3Bucket, mqApiKey, faceCollection, cctvEnabled, repos }) {
  console.log(`${c.bold}Complete these tasks after the containers are healthy:${c.reset}\n`);

  let n = 1;
  const step = (msg) => console.log(`  ${c.bold}${n++}.${c.reset} ${msg}`);

  step(`Verify all containers are healthy:\n     docker compose ps  (run in each repo folder)`);

  step(`EMQX — Create API credentials:\n` +
       `     Open ${c.cyan}http://localhost:18083${c.reset} (user: admin)\n` +
       `     Go to System → API Keys → Create key\n` +
       `     Update MQ_API_KEY / MQ_API_SECRET in:\n` +
       `       • SCE-PHP-SYSTEMS/.env\n` +
       `       • SCE-Python-Service/.env\n` +
       `     Then restart both containers: docker compose up -d`);

  if (isOnPrem) {
    step(`MinIO — Create bucket "${s3Bucket}":\n` +
         `     Open ${c.cyan}http://localhost:9011${c.reset}\n` +
         `     Log in → Create bucket → name: ${s3Bucket}\n` +
         `     Set bucket policy to allow app access`);
  }

  if (!faceCollection) {
    step(`AWS Rekognition — Create a face collection:\n` +
         `     aws rekognition create-collection --collection-id <your-name>\n` +
         `     Update FACE_COLLECTION in SCE-PHP-SYSTEMS/.env`);
  }

  step(`SCE-PHP-SYSTEMS — Run database installer (first time only):\n` +
       `     cd ${repos.php || 'SCE-PHP-SYSTEMS'}\n` +
       `     npm install && node install_system.js`);

  step(`Firebase — Copy service account JSON into the PHP container:\n` +
       `     docker cp firebase-service-account.json sce-php-app:/var/www/sce/\n` +
       `     (path configured as SERVICE_ACCOUNT_PATH)`);

  step(`APNs — Copy .p8 key file into the PHP container:\n` +
       `     docker cp AuthKey_XXXX.p8 sce-php-app:/var/www/sce/apns.p8\n` +
       `     (path configured as KEYPATH)`);

  step(`eAssist — Set SCE_PASSWORD in eAssist-AI-Service/.env:\n` +
       `     This should match an admin account in SCE-PHP-SYSTEMS (UAC)\n` +
       `     Then restart: docker compose up -d`);

  if (cctvEnabled) {
    step(`CCTV — Add VSS RSA keys to SCE-Python-Service/.env:\n` +
         `     VSS_PRIVATE_KEY and VSS_PUBLIC_KEY must be filled manually\n` +
         `     (obtain from your VSS administrator)`);
  }

  step(`Verify the system is working:\n` +
       `     • PHP:    ${domainUrl}/UAC\n` +
       `     • Python: ${domainUrl.replace(domain, 'localhost')}:8000/docs\n` +
       `     • CPA:    ${domainUrl}/CPA\n` +
       `     • AI:     ${domainUrl.replace(domain, 'localhost')}:3002`);

  console.log();
  console.log(`${c.green}${c.bold}All .env files written. See above checklist for remaining manual steps.${c.reset}\n`);
}

// ── Entry ─────────────────────────────────────────────────────────────────────
main().catch(e => {
  err(`Fatal error: ${e.message}`);
  console.error(e.stack);
  if (rl) rl.close();
  process.exit(1);
});
