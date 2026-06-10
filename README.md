# SCE Ecosystem — Installation Guide

> Smart Country Ecosystem · Full-stack deployment guide.
> Follow each section **in order** — every layer depends on the one before it.

---

## Table of Contents

1. [Host Machine Prerequisites](#1-host-machine-prerequisites)
2. [Clone All Repositories](#2-clone-all-repositories)
3. [Environment Setup Wizard](#3-environment-setup-wizard)
4. [VaultFlow360 — PostgreSQL HA](#4-vaultflow360--postgresql-ha)
5. [Prerequisites — Redis · EMQX · MinIO](#5-prerequisites--redis--emqx--minio)
6. [SCE-PHP-SYSTEMS — PHP Web App](#6-sce-php-systems--php-web-app)
7. [SCE-Python-Service — FastAPI + Workers](#7-sce-python-service--fastapi--workers)
8. [eAssist-AI-Service — AI Assistant](#8-eassist-ai-service--ai-assistant)
9. [SCE-Vue-CPA — Citizen Portal App](#9-sce-vue-cpa--citizen-portal-app)
10. [Startup Order](#10-startup-order)
11. [Docker Network Map](#11-docker-network-map)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Host Machine Prerequisites

Install all tools below before running anything else.

### Required for all deployments

| Tool | Min Version | Download |
|------|-------------|----------|
| **Git** | 2.x | https://git-scm.com/downloads |
| **Docker Desktop** | 4.x | https://www.docker.com/products/docker-desktop |
| **Docker Compose** | v2 (bundled with Docker Desktop) | included above |
| **Node.js** | 18+ | https://nodejs.org/en/download |

### Required for building the Citizen Portal App (CPA)

| Tool | Min Version | Install |
|------|-------------|---------|
| **Bun** | 1.3+ | https://bun.sh |
| **Quasar CLI** | latest | `bun install -g @quasar/cli` |

### Required for Android builds

| Tool | Notes | Download |
|------|-------|----------|
| **Android Studio** | Includes Android SDK | https://developer.android.com/studio |
| **JDK** | 17+ (bundled in Android Studio) | included above |

> After installing Android Studio, open **SDK Manager → SDK Tools** and ensure **Android SDK Build-Tools** is installed.
> Set the `ANDROID_HOME` environment variable to your SDK path.

### Required for iOS builds (macOS only)

| Tool | Notes | Download |
|------|-------|----------|
| **Xcode** | 15+ | https://apps.apple.com/app/xcode/id497799835 |
| **CocoaPods** | 1.13+ | `sudo gem install cocoapods` |
| **Apple Developer Account** | Free (device testing) or Paid (App Store) | https://developer.apple.com |

### Required for local development only (not needed for Docker)

| Tool | Version | Download |
|------|---------|----------|
| **PHP** | 8.2 | https://www.php.net/downloads |
| **Composer** | 2.x | https://getcomposer.org/download |
| **Python** | 3.11 | https://www.python.org/downloads |

---

## 2. Clone All Repositories

All repositories must live in a **single parent folder**. Use the setup script — it handles everything interactively.

### Option A — Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.sh | bash
```

Or with wget:
```bash
wget -qO- https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.sh | bash
```

### Option B — Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.js | node
```

Or download and double-click the batch file:
```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.bat -OutFile setup.bat
.\setup.bat
```

### Option C — Anywhere Node.js is installed

```bash
curl -fsSL https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.js -o setup.js
node setup.js
```

### What the script asks

```
Parent folder name [SCE-ECOSYSTEM]: _

Clone VaultFlow360        (PostgreSQL HA cluster)?           [Y/n]:
Clone SCE-Installation    (Installer + infra prerequisites)? [Y/n]:
Clone SCE-PHP-SYSTEMS     (UAC / CRMS / EMS — PHP app)?      [Y/n]:
Clone SCE-Python-Service  (FastAPI + BullMQ workers)?        [Y/n]:
Clone SCE-Vue-CPA         (Citizen Portal App)?              [Y/n]:
Clone eAssist-AI-Service  (AI assistant)?                    [Y/n]:

GitHub Personal Access Token (leave blank if repos are public): _
```

Press **Enter** to accept Yes. Type **N** to skip. If a folder already has a `.git` directory the script runs `git pull` instead.

### Resulting folder structure

```
SCE-ECOSYSTEM/
├── VaultFlow360/          # PostgreSQL HA cluster + backup API
├── SCE-Installation/      # This repo — infra setup (Redis, EMQX, MinIO)
├── SCE-PHP-SYSTEMS/       # PHP web app (UAC / CRMS / EMS)
├── SCE-Python-Service/    # FastAPI API + BullMQ workers
├── SCE-Vue-CPA/           # Citizen Portal App (Quasar PWA / Android / iOS)
└── eAssist-AI-Service/    # AI assistant (Bun + CopilotKit)
```

### Repository links

| Repository | Description |
|------------|-------------|
| [VaultFlow360](https://github.com/dev-itbs/VaultFlow360) | PostgreSQL HA with replication, Pgpool, WAL archiving, backup API |
| [SCE-Installation](https://github.com/dev-itbs/SCE-Installation) | This repo — Redis, EMQX, MinIO setup + clone scripts |
| [SCE-PHP-SYSTEMS](https://github.com/dev-itbs/SCE-PHP-SYSTEMS) | PHPMaker 2024 web app — UAC, CRMS, EMS subsystems |
| [SCE-Python-Service](https://github.com/dev-itbs/SCE-Python-Service) | FastAPI backend, KYC, records import/export, CCTV workers |
| [SCE-Vue-CPA](https://github.com/dev-itbs/SCE-Vue-CPA) | Quasar Vue 3 citizen portal — PWA, Android, iOS |
| [eAssist-AI-Service](https://github.com/dev-itbs/eAssist-AI-Service) | Bun + CopilotKit AI assistant service |

---

## 3. Environment Setup Wizard

After cloning, run the wizard instead of editing `.env` files manually. It scans all repos, asks for credentials once, auto-fills every `.env`, and optionally starts all Docker stacks.

### Run the wizard

**Linux / macOS:**
```bash
bash SCE-Installation/docker-setup/configure.sh
```

**Windows (PowerShell / CMD):**
```bat
SCE-Installation\docker-setup\configure.bat
```

**Cross-platform (Node.js):**
```bash
node SCE-Installation/docker-setup/configure.js
```

### What the wizard configures

| Step | What it asks |
|------|-------------|
| Deployment type | On-prem (MinIO) or cloud S3 |
| Domain & identity | Public domain, LGU code, LGU name |
| Database | All PostgreSQL and Pgpool passwords |
| Redis & EMQX | Redis password, EMQX dashboard password, MQTT topic |
| S3 / MinIO | Bucket, region, access key, secret |
| PHP settings | Mailgun, Firebase/APNs, CCTV toggle, ICE servers, face collection |
| Python settings | OpenAI API key, JWT secret, CCTV/VSS details |
| eAssist settings | LLM model, OpenAI key |

### What it auto-fills without asking

- All Docker container hostnames (`postgres-wal-pgpool`, `sce-redis`, `sce-emqx`, `sce-minio`)
- `LGU` / `LGU_NAME` / `MQ_TOPIC` — derived from the parent folder name
- `QRCODE_BASE_URL`, `CPA_DOWNLOAD_URL`, `SCE_SETTINGS_API_URL` — derived from the domain
- Upload paths and S3 prefixes — derived from the ecosystem folder name
- Cross-service API URLs (`PYTHON_API_URL`, `CRMS_API_BASE_URL`, `EMS_API_BASE_URL`)

> If you prefer to configure `.env` files manually, skip this step and follow Sections 4–8.

---

## 4. VaultFlow360 — PostgreSQL HA

The database layer. **All other services connect through it.** Start this first.

### 4.1 Configure

```bash
cd SCE-ECOSYSTEM/VaultFlow360
```

Edit `postgres-wal.env` (or let the wizard do it):

```env
POSTGRES_PASSWORD=your_strong_password
POSTGRES_SUPERUSER_PASSWORD=your_strong_password
REPMGR_PASSWORD=your_strong_password
PGPOOL_ADMIN_PASSWORD=your_strong_password
BACKUP_ADMIN_PASSWORD=your_strong_password
BACKUP_API_KEY=your_api_key

# Absolute path on the host for the backup database file
BACKUP_API_DB_PATH=/your/path/VaultFlow360/backups/data/backup-api.db

BACKUP_TIMEZONE=Asia/Manila
```

**Optional — S3 backup storage:**

```env
BACKUP_S3_ENABLED=true
BACKUP_S3_ENDPOINT=http://sce-minio:9000     # on-prem MinIO
# or: https://sgp1.digitaloceanspaces.com    # DigitalOcean Spaces
BACKUP_S3_BUCKET=your-bucket
BACKUP_S3_ACCESS_KEY_ID=your_key
BACKUP_S3_SECRET_ACCESS_KEY=your_secret
BACKUP_S3_FORCE_PATH_STYLE=true              # required for MinIO
```

### 4.2 Start

```bash
docker compose --env-file postgres-wal.env up -d --build
```

### 4.3 Verify

```bash
docker compose --env-file postgres-wal.env ps
```

All containers must show **healthy** before continuing:

| Container | Role |
|-----------|------|
| `postgres-wal-pg-0` | Primary PostgreSQL node |
| `postgres-wal-pg-1` | Streaming replica |
| `postgres-wal-pg-2` | Streaming replica |
| `postgres-wal-pgpool` | Load balancer — single connection entrypoint |
| `postgres-wal-backup-api` | Backup scheduler + admin API |

### 4.4 Access points

| What | Address |
|------|---------|
| PostgreSQL (from host) | `localhost:55432` |
| PostgreSQL (container-to-container) | `postgres-wal-pgpool:5432` |
| Backup API admin UI | http://localhost:8090/admin |
| Backup API Swagger | http://localhost:8090/swagger |

---

## 5. Prerequisites — Redis · EMQX · MinIO

Cache, message broker, and optional on-prem object storage.

### 5.1 Configure

```bash
cd SCE-ECOSYSTEM/SCE-Installation/prerequisite
cp .env.example .env
```

Edit `.env`:

```env
# Required — set strong passwords
REDIS_PASSWORD=your_strong_password
EMQX_DASHBOARD_PASSWORD=your_strong_password

# On-prem only: set COMPOSE_PROFILES=onprem to also start MinIO
# Cloud deployments: leave empty
COMPOSE_PROFILES=

# MinIO credentials (only used when COMPOSE_PROFILES=onprem)
MINIO_ACCESS_KEY=your_access_key
MINIO_SECRET_KEY=your_strong_password
```

### 5.2 Start

```bash
docker compose up -d
```

### 5.3 Post-boot — Create EMQX API credentials

1. Open http://localhost:18083 (user: `admin`)
2. Go to **System → API Keys → Create Key**
3. Copy the API Key and Secret into:
   - `SCE-PHP-SYSTEMS/.env` → `MQ_API_KEY` / `MQ_API_SECRET`
   - `SCE-Python-Service/.env` → `EMQX_KEY` / `EMQX_SECRET`
4. Restart both app containers after updating

### 5.4 Post-boot — Create MinIO bucket (on-prem only)

1. Open http://localhost:9011
2. Log in with your MinIO credentials
3. Create a bucket matching the name in `S3_BUCKET` / `S3_BUCKET_NAME`

### 5.5 Access points

| Service | Address | Notes |
|---------|---------|-------|
| Redis | `localhost:6379` | Password protected |
| EMQX Dashboard | http://localhost:18083 | Default user: `admin` |
| EMQX MQTT | `localhost:1883` | Standard MQTT |
| EMQX WebSocket | `localhost:8083` | MQTT over WS |
| EMQX WSS | `localhost:2096` | MQTT over WSS (secure) |
| MinIO Console | http://localhost:9011 | On-prem only |
| MinIO API | `localhost:9010` | On-prem only |

---

## 6. SCE-PHP-SYSTEMS — PHP Web App

PHPMaker 2024 app serving UAC, CRMS, and EMS.

### 6.1 Configure

```bash
cd SCE-ECOSYSTEM/SCE-PHP-SYSTEMS
cp .env.example .env
```

Key values to set (use **container hostnames**, not `localhost`):

```env
# Database
DB_HOST=postgres-wal-pgpool
DB_PORT=5432
DB_NAME=postgres
DB_USER=appuser
DB_PASSWORD=your_postgres_password

# Redis
REDIS_HOST=sce-redis
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

# LGU identity (auto-filled by wizard)
LGU=your-lgu-code
LGU_NAME=Your LGU Name

# Python service
PYTHON_API_URL=http://sce-python-api:8000

# Cookie settings
COOKIE_DOMAIN=yourdomain.ph
COOKIE_SECURE=true

# MQTT
MQ_WS_URL=ws://sce-emqx:8083/mqtt
MQ_TOPIC=your-lgu-code
MQ_API_KEY=                          # fill after EMQX is running
MQ_API_SECRET=                       # fill after EMQX is running
```

### 6.2 Run the database installer (first time only)

```bash
npm install
node install_system.js
```

This creates the database schema, runs migrations, and installs BullMQ Lua scripts into vendor.

### 6.3 Build and start

```bash
docker compose up -d --build
```

### 6.4 Access points

| Subsystem | URL |
|-----------|-----|
| UAC — User Access Control | http://localhost/UAC |
| CRMS — Citizen Records | http://localhost/CRMS |
| EMS — Emergency Management | http://localhost/EMS |
| CPA — Citizen Portal assets | http://localhost/CPA |

---

## 7. SCE-Python-Service — FastAPI + Workers

Handles KYC face verification, records import/export, AI document processing, and CCTV management.

### 7.1 Configure

```bash
cd SCE-ECOSYSTEM/SCE-Python-Service
```

Key values to set (use **container hostnames**):

```env
# Database
UAC_DB_URL=postgresql://appuser:your_password@postgres-wal-pgpool:5432/postgres
IMPORT_DB_URL=postgresql://appuser:your_password@postgres-wal-pgpool:5432/postgres

# Redis
REDIS_HOST=sce-redis
REDIS_PASSWORD=your_redis_password

# JWT
JWT_SECRET_KEY=your_jwt_secret

# S3 storage
S3_ENDPOINT_URL=https://sgp1.digitaloceanspaces.com
# On-prem MinIO: S3_ENDPOINT_URL=http://sce-minio:9000
S3_ACCESS_KEY=your_key
S3_SECRET_KEY=your_secret
S3_BUCKET_NAME=your_bucket

# AI provider (hardcoded to OpenAI)
AI_PROVIDER=openai
OPENAI_API_KEY=your_openai_key
OPENAI_MODEL_NAME=gpt-4o-mini

# CCTV — keep both in sync
CCTV_SERVICE_ENABLED=false
COMPOSE_PROFILES=
# To enable CCTV: CCTV_SERVICE_ENABLED=true  and  COMPOSE_PROFILES=cctv
```

### 7.2 Build and start

```bash
docker compose up -d --build
```

### 7.3 Access points

| Service | URL |
|---------|-----|
| FastAPI | http://localhost:8000 |
| API Docs (Swagger) | http://localhost:8000/docs |
| Stream server (CCTV only) | http://localhost:8081 |

---

## 8. eAssist-AI-Service — AI Assistant

Bun + CopilotKit AI assistant that connects to CRMS and EMS APIs.

### 8.1 Configure

```bash
cd SCE-ECOSYSTEM/eAssist-AI-Service
```

Edit `.env`:

```env
OPENAI_API_KEY=your_openai_key
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
PORT=3002
NODE_ENV=production

# Must match an admin account in SCE-PHP-SYSTEMS (UAC)
SCE_USERNAME=admin
SCE_PASSWORD=your_sce_admin_password

CRMS_API_BASE_URL=http://sce-php-app/CRMS
EMS_API_BASE_URL=http://sce-php-app/EMS
```

### 8.2 Build and start

```bash
docker compose up -d --build
```

**Accessible at:** http://localhost:3002

---

## 9. SCE-Vue-CPA — Citizen Portal App

Quasar Vue 3 app. Deployable as a PWA (static files served by PHP), Android APK, or iOS app.

### 9.1 Install dependencies

```bash
cd SCE-ECOSYSTEM/SCE-Vue-CPA
bun install
```

### 9.2 Configure

Edit `quasar.config.js` — set your API base URL, Google Maps key, and MQTT broker URL.

---

### 9.3 Build — PWA

```bash
bunx @quasar/cli build -m pwa
```

Output lands in `dist/pwa/`. Copy the contents into `SCE-PHP-SYSTEMS/CPA/` to serve it at `/CPA`.

---

### 9.4 Build — Android APK

**One-time machine setup:**

1. Install [Android Studio](https://developer.android.com/studio)
2. Open Android Studio → **SDK Manager → SDK Tools** → install **Android SDK Build-Tools**
3. Set `ANDROID_HOME` environment variable:
   - Windows: `C:\Users\<you>\AppData\Local\Android\Sdk`
   - macOS/Linux: `~/Library/Android/sdk`

**Build:**

```bash
# Build web assets for Capacitor
bunx @quasar/cli build -m capacitor -T android

# Sync native project
cd src-capacitor
npx cap sync android

# Open in Android Studio
npx cap open android
```

In Android Studio:
- **Debug / run on device:** click **Run (▶)**
- **Release APK:** Build → Generate Signed Bundle / APK

**Bump version before each release** — `src-capacitor/android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        versionCode 5         // increment by 1
        versionName "1.0.5"
    }
}
```

---

### 9.5 Build — iOS (macOS only)

**One-time machine setup:**

```bash
# Install Quasar CLI globally
bun install -g @quasar/cli

# Install Capacitor dependencies
cd src-capacitor && bun install

# Replace deprecated capacitor-updater with maintained fork
bun remove capacitor-updater
bun add @capgo/capacitor-updater

# Add iOS platform
bunx @capacitor/cli add ios
```

Edit `src-capacitor/ios/App/Podfile`:

```ruby
# From:
pod 'CapacitorUpdater', :path => '../../node_modules/capacitor-updater'
# To:
pod 'CapgoCapacitorUpdater', :path => '../../node_modules/@capgo/capacitor-updater'
```

```bash
# Install CocoaPods
cd ios/App
export LANG=en_US.UTF-8
pod install
```

**Build and run:**

```bash
# From project root
bunx @quasar/cli build -m capacitor -T ios

cd src-capacitor
bunx @capacitor/cli sync ios

# ALWAYS open .xcworkspace — NOT .xcodeproj
open ios/App/App.xcworkspace
```

In Xcode:
- **Simulator:** Select any iPhone simulator → click **Run (▶)**
- **Physical device:** Connect device → Signing & Capabilities → select team → **Run (▶)**
- **App Store / TestFlight:** Select "Any iOS Device" → Product → Archive → upload

**Daily workflow:**

```bash
bunx @quasar/cli build
cd src-capacitor && bunx @capacitor/cli sync ios
open ios/App/App.xcworkspace
```

---

## 10. Startup Order

Run in this order on every fresh server start. The networks created by the infra stacks must exist before app containers start.

```bash
# 1. Database
cd SCE-ECOSYSTEM/VaultFlow360
docker compose --env-file postgres-wal.env up -d --build

# 2. Infra (Redis, EMQX, MinIO)
cd ../SCE-Installation/prerequisite
docker compose up -d

# 3. PHP app
cd ../../SCE-PHP-SYSTEMS
docker compose up -d --build

# 4. Python service
cd ../SCE-Python-Service
docker compose up -d --build

# 5. AI service
cd ../eAssist-AI-Service
docker compose up -d --build
```

> **SCE-Vue-CPA** is a build artifact — its output is static files copied into the PHP container or served from a CDN. It does not run as a separate Docker service.

> **Tip:** Use the wizard (`configure.js / .sh / .bat`) to start all stacks automatically after filling in credentials.

---

## 11. Docker Network Map

All app containers join infra networks via `external: true` — no host-port tricks needed for internal traffic.

```
postgres-wal-network          (created by VaultFlow360)
  └── postgres-wal-pgpool:5432
        ├── sce-php-app
        └── sce-python-api / workers

sce_infra_network             (created by SCE-Installation/prerequisite)
  ├── sce-redis:6379
  ├── sce-emqx:1883 / 8083 / 2096
  └── sce-minio:9000  (on-prem only)
        ├── sce-php-app
        ├── sce-python-api / workers
        └── eassist-ai
```

### Container hostname reference

| Service | Hostname (container-to-container) | Host port |
|---------|----------------------------------|-----------|
| PostgreSQL | `postgres-wal-pgpool` | `55432` |
| Redis | `sce-redis` | `6379` |
| EMQX MQTT | `sce-emqx` | `1883` |
| EMQX WebSocket | `sce-emqx` | `8083` |
| EMQX WSS | `sce-emqx` | `2096` |
| EMQX Dashboard | `sce-emqx` | `18083` |
| MinIO API | `sce-minio` | `9010` |
| MinIO Console | `sce-minio` | `9011` |
| PHP app | `sce-php-app` | `80` |
| Python API | `sce-python-api` | `8000` |
| Stream server | `sce-stream-server` | `8081` |
| AI service | `eassist-ai` | `3002` |
| Backup API | `postgres-wal-backup-api` | `8090` |

---

## 12. Troubleshooting

**`network postgres-wal-network not found`**
Start VaultFlow360 first. Docker creates the network on `docker compose up`.

**`network sce_infra_network not found`**
Start `SCE-Installation/prerequisite` before starting the app stacks.

**PHP BullMQ error: `getOrSetMaxEvents`**
Run `npm run install-bullmq-lua` inside `SCE-PHP-SYSTEMS/`. In Docker this runs automatically at build time.

**Python workers not consuming queue jobs**
Check `REDIS_HOST=sce-redis` in `SCE-Python-Service/.env` and confirm the prerequisite stack is running.

**CCTV containers keep restarting**
Set `CCTV_SERVICE_ENABLED=false` and `COMPOSE_PROFILES=` (empty) in `SCE-Python-Service/.env`, then `docker compose up -d`.

**Port 5432 conflict with local PostgreSQL**
VaultFlow360 exposes Postgres on host port `55432` by default (`POSTGRES_HOST_PORT=55432` in `postgres-wal.env`).

**eAssist cannot reach PHP API**
Confirm `sce-php-app` is running and that `eAssist-AI-Service/.env` has `CRMS_API_BASE_URL=http://sce-php-app/CRMS`. Both containers must be on `sce_infra_network`.

**iOS: `Unable to find module dependency: Capacitor`**
You opened `.xcodeproj` instead of `.xcworkspace`. Close Xcode and run:
```bash
open src-capacitor/ios/App/App.xcworkspace
```

**iOS: CocoaPods encoding error**
```bash
export LANG=en_US.UTF-8
cd src-capacitor/ios/App && pod install
```

**Android: `ANDROID_HOME not set`**
```bash
# macOS/Linux — add to ~/.bashrc or ~/.zshrc
export ANDROID_HOME=~/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools
```
