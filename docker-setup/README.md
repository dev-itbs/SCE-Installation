# SCE Ecosystem — Docker Environment Setup Wizard

`configure.js` is an interactive Node.js script that:

1. **Scans** all sibling folders to detect which SCE repos are present
2. **Asks** shared infrastructure credentials once (DB, Redis, EMQX, S3/MinIO)
3. **Auto-derives** per-system values (Docker hostnames, folder paths, public URLs)
4. **Writes** all `.env` files across every repo
5. **Optionally starts** all Docker stacks in the correct order

---

## Requirements

- [Node.js 18+](https://nodejs.org/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- All repos cloned into the same parent folder (use `../setup.js` to clone them)

---

## Usage

```bash
# From the ecosystem root, after cloning all repos:
node SCE-Installation/docker-setup/configure.js
```

Or if you are already inside this folder:

```bash
node configure.js
```

---

## What it writes

| Repo | File |
|---|---|
| VaultFlow360 | `postgres-wal.env` |
| SCE-Installation/prerequisite | `.env` |
| SCE-PHP-SYSTEMS | `.env` |
| SCE-Python-Service | `.env` |
| eAssist-AI-Service | `.env` |

---

## Auto-derived values

The wizard **never asks** for these — it calculates them automatically:

| Variable | Derived from |
|---|---|
| `LGU` / `LGU_NAME` | Parent ecosystem folder name |
| `MQ_TOPIC` / `EMQX_TOPIC` | Parent ecosystem folder name (slugified) |
| `S3_UPLOAD_PATH` / `EMS_FILE_PATH` | Ecosystem folder name used as S3 prefix |
| `QRCODE_BASE_URL` | Domain + `/CPA/#/deeplink?data=` |
| `CPA_DOWNLOAD_URL` | Domain + `/CPA/download` |
| `CPA_LOGIN_URL` | Domain + `/CPA/#/login` |
| `SCE_SETTINGS_API_URL` | Domain + `/UAC/api` |
| `DB_HOST` | `postgres-wal-pgpool` (Docker hostname) |
| `REDIS_HOST` | `sce-redis` (Docker hostname) |
| `MQ_API_URL` / `MQ_WS_URL` | `sce-emqx` (Docker hostname) |
| `PYTHON_API_URL` | `http://sce-python-api:8000` |
| `CRMS_API_BASE_URL` | `http://sce-php-app/CRMS` |
| `EMS_API_BASE_URL` | `http://sce-php-app/EMS` |
| `S3_ENDPOINT` (on-prem) | `http://sce-minio:9000` |
| `UPLOAD_TEMP_PATH` | `/var/www/sce/temp_uploads/` (container path) |
| `UPLOAD_PATH` | `/tmp/imports` (container path) |
| `STREAMS_DIR` | `/app/streams` (container path) |

---

## Already configured?

If you have already run the wizard and just want to restart Docker stacks, answer **Y** to the first question. The script will skip re-asking all credentials and go straight to `docker compose up -d` in each repo.

---

## Post-install manual steps

After all containers are healthy, complete the following:

### 1. EMQX — Create API credentials

1. Open `http://localhost:18083` (default user: `admin`)
2. Log in with the password you set during configuration
3. Go to **System → API Keys → Create Key**
4. Copy the generated **API Key** and **Secret**
5. Update both values in:
   - `SCE-PHP-SYSTEMS/.env` → `MQ_API_KEY` and `MQ_API_SECRET`
   - `SCE-Python-Service/.env` → `EMQX_KEY` and `EMQX_SECRET`
6. Restart both containers:
   ```bash
   # in SCE-PHP-SYSTEMS/
   docker compose up -d
   # in SCE-Python-Service/
   docker compose up -d
   ```

### 2. MinIO — Create bucket (on-prem only)

1. Open `http://localhost:9011`
2. Log in with the MinIO credentials you set during configuration
3. Click **Create Bucket** — use the same name you entered for `S3_BUCKET_NAME`
4. Set the bucket access policy to allow the application

### 3. Face Collection — AWS Rekognition

If using AWS Rekognition for face login:

```bash
aws rekognition create-collection --collection-id <your-collection-name>
```

Update `FACE_COLLECTION` in `SCE-PHP-SYSTEMS/.env` and restart.

### 4. Database installer (first boot only)

```bash
cd SCE-PHP-SYSTEMS
# Install BullMQ Lua scripts (if using gensart-x/bullmq-php)
node install-bullmq-lua.js

# Run the PHP system installer
# Open the browser: https://your-domain/UAC/install
```

### 5. Firebase — Service account JSON

Copy your Firebase service account key into the PHP container:

```bash
docker cp /path/to/firebase-service-account.json sce-php-app:/var/www/sce/firebase-service-account.json
```

The path inside the container is controlled by `SERVICE_ACCOUNT_PATH` in `SCE-PHP-SYSTEMS/.env`.

### 6. APNs — iOS push notification key

Copy your `.p8` APNs key into the PHP container:

```bash
docker cp /path/to/AuthKey_XXXX.p8 sce-php-app:/var/www/sce/apns.p8
```

The path is controlled by `KEYPATH` in `SCE-PHP-SYSTEMS/.env`.

### 7. eAssist — Admin password

Set `SCE_PASSWORD` in `eAssist-AI-Service/.env` to match an admin account in the SCE UAC system, then restart:

```bash
cd eAssist-AI-Service
docker compose up -d
```

### 8. CCTV — VSS RSA keys (if CCTV enabled)

Add the VSS RSA key pair to `SCE-Python-Service/.env`:

```env
VSS_PRIVATE_KEY=-----BEGIN RSA PRIVATE KEY-----...
VSS_PUBLIC_KEY=-----BEGIN PUBLIC KEY-----...
```

Obtain these from your VSS (video surveillance system) administrator.

---

## Docker startup order

Always start stacks in this order to respect network and database dependencies:

```text
1. VaultFlow360          (PostgreSQL HA — creates postgres-wal-network)
2. SCE-Installation/prerequisite  (Redis, EMQX, MinIO — creates sce_infra_network)
3. SCE-PHP-SYSTEMS       (requires DB + Redis + EMQX)
4. SCE-Python-Service    (requires DB + Redis + EMQX)
5. eAssist-AI-Service    (requires PHP app to be up for API calls)
```

---

## Re-running the wizard

You can safely re-run `configure.js` at any time. It will overwrite `.env` files. If you want to keep existing values, choose the "already configured" shortcut at the first prompt.
