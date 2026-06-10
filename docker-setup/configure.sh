#!/usr/bin/env bash
# SCE Ecosystem — Docker Environment Setup Wizard (Bash)
#
# Usage:
#   bash configure.sh
#
# Must be run from the SCE-Installation/docker-setup/ directory,
# or any path — it resolves the ecosystem root automatically.

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[36m'; GREEN='\033[32m'
YELLOW='\033[33m'; RED='\033[31m'; GREY='\033[90m'; BLUE='\033[34m'; RESET='\033[0m'

log()   { echo -e "${CYAN}${1}${RESET}"; }
ok()    { echo -e "${GREEN}  ✔ ${1}${RESET}"; }
warn()  { echo -e "${YELLOW}  ⚠ ${1}${RESET}"; }
info()  { echo -e "${BLUE}  ℹ ${1}${RESET}"; }
err()   { echo -e "${RED}  ✖ ${1}${RESET}"; }
dim()   { echo -e "${GREY}    ${1}${RESET}"; }
title() { echo -e "\n${BOLD}${CYAN}━━━  ${1}  ━━━${RESET}\n"; }
hr()    { echo -e "${GREY}$(printf '─%.0s' {1..70})${RESET}"; }

# All prompt functions store their result in REPLY — never use $() with these.
ask() {
    local prompt="$1" default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" [${GREY}${default}${RESET}]"
    printf "  %b%b: " "${prompt}" "${hint}" >/dev/tty
    read -r REPLY </dev/tty
    [[ -z "$REPLY" ]] && REPLY="$default"
}

ask_required() {
    local prompt="$1"
    REPLY=""
    while [[ -z "$REPLY" ]]; do
        ask "${prompt} ${RED}(required)${RESET}"
        [[ -z "$REPLY" ]] && warn "This field is required."
    done
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
    ask "${prompt} ${hint}"
    [[ -z "$REPLY" ]] && REPLY="$default"
    [[ "${REPLY,,}" == y* ]] && REPLY="true" || REPLY="false"
}

rand_secret() {
    local bytes="${1:-32}"
    head -c "$bytes" /dev/urandom | base64 | tr -d '=/+' | head -c $(( bytes * 2 )) || \
        cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' || \
        date +%s%N | sha256sum | head -c 32
}

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-\|-$//g'
}

write_env() {
    local file="$1"; shift
    printf '%s\n' "$@" > "$file"
    ok "Written: ${file#${ROOT}/}"
}

docker_up() {
    local dir="$1" cmd="${2:-docker compose up -d --build}"
    (cd "$dir" && eval "$cmd")
}

# ── Discover ecosystem root ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ECOSYSTEM_NAME="$(basename "$ROOT")"

# ── Discover repos by fuzzy-matching folder names ─────────────────────────────
find_repo() {
    local keyword="$1"
    for dir in "$ROOT"/*/; do
        local name
        name="$(basename "$dir")"
        if echo "${name,,}" | grep -qi "$keyword"; then
            echo "${dir%/}"
            return
        fi
    done
    echo ""
}

DIR_VAULT=$(find_repo "vault")
DIR_PREREQ=$(find_repo "installation")
DIR_PHP=$(find_repo "php")
DIR_PYTHON=$(find_repo "python")
DIR_EASSIST=$(find_repo "eassist")

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║       SCE Ecosystem — Docker Environment Setup        ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  Ecosystem root: ${BOLD}${ROOT}${RESET}\n"

# ── Resolve missing repos ─────────────────────────────────────────────────────
resolve_repo() {
    local var="$1" label="$2" current="$3"
    if [[ -n "$current" ]]; then
        ok "Found ${label} → ${current#${ROOT}/}"
    else
        warn "Could not find ${label}"
        ask "  Enter folder name inside ${ROOT} (or leave blank to skip)"
        if [[ -n "$REPLY" ]]; then
            local full="$REPLY"
            [[ "${full:0:1}" != "/" ]] && full="${ROOT}/${REPLY}"
            if [[ -d "$full" ]]; then
                eval "${var}=\"${full}\""
                ok "Using ${full}"
            else
                warn "Path not found: ${full} — skipping ${label}"
            fi
        else
            dim "Skipping ${label}"
        fi
    fi
}

log "Scanning for repositories..."
echo ""
resolve_repo DIR_VAULT   "VaultFlow360        (PostgreSQL HA)"       "$DIR_VAULT"
resolve_repo DIR_PREREQ  "SCE-Installation    (This installer repo)" "$DIR_PREREQ"
resolve_repo DIR_PHP     "SCE-PHP-SYSTEMS     (PHP web app)"         "$DIR_PHP"
resolve_repo DIR_PYTHON  "SCE-Python-Service  (FastAPI + workers)"   "$DIR_PYTHON"
resolve_repo DIR_EASSIST "eAssist-AI-Service  (AI assistant)"        "$DIR_EASSIST"
echo ""

# ── Already configured? ───────────────────────────────────────────────────────
hr
ask_yn "Already configured .env files — just (re)start Docker?" "n"
SKIP_CONFIG="$REPLY"

if [[ "$SKIP_CONFIG" == "true" ]]; then
    warn "Skipping env generation. Starting Docker stacks only."
    START_DOCKER="true"
else

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 1 — Deployment Type"
ask_yn "Is this an ON-PREM deployment? (MinIO instead of cloud S3)" "n"
IS_ONPREM="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 2 — Domain & Identity"
info "Enter your public domain, or press Enter to use localhost for local development."
ask "System domain (no https://, no trailing slash)" "localhost"
DOMAIN="$REPLY"
if [[ "$DOMAIN" == "localhost" || "$DOMAIN" == localhost:* ]]; then
    DOMAIN_URL="http://${DOMAIN}"
else
    DOMAIN_URL="https://${DOMAIN}"
fi
ask "LGU code" "$(slugify "$ECOSYSTEM_NAME")"
LGU_CODE="$REPLY"
ask "LGU full name" "${ECOSYSTEM_NAME//-/ }"
LGU_NAME="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 3 — Database (VaultFlow360 / PostgreSQL)"
ask "PostgreSQL database name" "postgres";          PG_DB="$REPLY"
ask "PostgreSQL app username" "appuser";            PG_USER="$REPLY"
ask "PostgreSQL app password" "$(rand_secret 16)";  PG_PASSWORD="$REPLY"
ask "PostgreSQL superuser password" "$(rand_secret 16)"; PG_SUPER_PW="$REPLY"
ask "Repmgr password" "$(rand_secret 16)";          REPMGR_PW="$REPLY"
ask "Pgpool admin username" "admin";                PGPOOL_USER="$REPLY"
ask "Pgpool admin password" "$(rand_secret 16)";    PGPOOL_PW="$REPLY"
ask "Backup API admin password" "$(rand_secret 16)"; BACKUP_PW="$REPLY"
ask "Backup API key" "$(rand_secret 12)";           BACKUP_KEY="$REPLY"
info "External Postgres host for Pgpool replication (leave blank if none)"
ask "PGPOOL_EXTERNAL_PG_HOST" "";                   PG_EXT_HOST="$REPLY"
PG_EXT_PORT=""
if [[ -n "$PG_EXT_HOST" ]]; then
    ask "PGPOOL_EXTERNAL_PG_PORT" "5432"; PG_EXT_PORT="$REPLY"
fi

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 4 — Redis & EMQX"
ask "Redis password" "$(rand_secret 16)";           REDIS_PASSWORD="$REPLY"
ask "EMQX dashboard password" "$(rand_secret 16)";  EMQX_DASH_PW="$REPLY"
info "EMQX API key and secret are created in the EMQX dashboard AFTER first boot."
ask "EMQX API key (optional, fill after boot)" "";  MQ_API_KEY="$REPLY"
ask "EMQX API secret (optional, fill after boot)" ""; MQ_API_SECRET="$REPLY"
ask "MQTT topic" "$LGU_CODE";                        MQ_TOPIC="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 5 — S3 / Object Storage"
if [[ "$IS_ONPREM" == "true" ]]; then
    info "On-prem: MinIO will be used. Container hostname is sce-minio."
    S3_ENDPOINT="http://sce-minio:9000"
    ask "MinIO bucket name" "$LGU_CODE";            S3_BUCKET="$REPLY"
    S3_REGION="us-east-1"
    ask "MinIO access key" "minioadmin";             S3_KEY="$REPLY"
    ask "MinIO secret key" "$(rand_secret 16)";      S3_SECRET="$REPLY"
    S3_FORCE_PATH_STYLE="true"
    info "Remember to create the bucket \"${S3_BUCKET}\" in MinIO console after first boot."
else
    info "Cloud: provide your S3-compatible storage credentials."
    ask "S3 endpoint URL (e.g. https://sgp1.digitaloceanspaces.com)"; S3_ENDPOINT="$REPLY"
    ask "S3 bucket name";                            S3_BUCKET="$REPLY"
    ask "S3 region" "sgp1";                          S3_REGION="$REPLY"
    ask "S3 access key";                             S3_KEY="$REPLY"
    ask "S3 secret key";                             S3_SECRET="$REPLY"
    S3_FORCE_PATH_STYLE="false"
fi
ask "S3 prefix for uploads" "${ECOSYSTEM_NAME}/uploads/";        S3_UPLOAD_PATH="$REPLY"
ask "S3 prefix for EMS incident files" "${ECOSYSTEM_NAME}/incident/"; EMS_FILE_PATH="$REPLY"
ask "S3 prefix for final uploads" "${ECOSYSTEM_NAME}/dest/";     UPLOAD_DEST_PATH="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 6 — PHP App Settings (SCE-PHP-SYSTEMS)"
ask "HASH_ID_SALT" "$(rand_secret 16)";              HASH_SALT="$REPLY"
ask "PARTNER_ID" "$LGU_CODE";                        PARTNER_ID="$REPLY"
ask "AWS Rekognition FACE_COLLECTION name";          FACE_COLLECTION="$REPLY"
ask "EMS Google Maps Map ID";                        GOOGLE_MAPS_ID="$REPLY"
ask "EMS dispatch level" "1";                        EMS_LEVEL="$REPLY"
ask "EMS boundary radius (km)" "10";                 EMS_BOUNDARY_KM="$REPLY"
info "Cookie domain = the domain where browsers send auth cookies."
ask "COOKIE_DOMAIN" "$DOMAIN";                       COOKIE_DOMAIN="$REPLY"
info "Mailgun is used for email notifications."
ask "Mailgun domain";                                MAILGUN_DOMAIN="$REPLY"
ask "Mailgun API key";                               MAILGUN_API_KEY="$REPLY"
ask "Mailgun validation key";                        MAILGUN_VAL_KEY="$REPLY"
info "Firebase — used for push notifications (Android/iOS)."
ask "FIREBASE_VAPID_KEY";                            FIREBASE_VAPID="$REPLY"
ask "FCM_ENDPOINT";                                  FCM_ENDPOINT="$REPLY"
ask "SERVICE_ACCOUNT_PATH (path inside container)" "/var/www/sce/firebase-service-account.json"
SERVICE_ACC_PATH="$REPLY"
ask "APNS_KEY_ID";                                   APNS_KEY_ID="$REPLY"
ask "APNS_TEAM_ID";                                  APNS_TEAM_ID="$REPLY"
ask "BUNDLE_ID (iOS app bundle ID)";                 BUNDLE_ID="$REPLY"
ask "KEYPATH (path to .p8 APNs key inside container)" "/var/www/sce/apns.p8"; KEYPATH="$REPLY"
info 'ICE_SERVERS — JSON array of STUN/TURN servers for WebRTC.'
ask 'ICE_SERVERS' '[{"urls":["stun:stun.l.google.com:19302"]}]';  ICE_SERVERS="$REPLY"
ask_yn "Enable CCTV integration?" "n";               CCTV_ENABLED="$REPLY"
ask "EASSIST_PLUGIN (URL path to dist-plugin)" "${DOMAIN_URL}/eassist/dist-plugin"; EASSIST_PLUGIN="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 7 — Python Service Settings"
ask "JWT_SECRET_KEY" "$(rand_secret 32)";            JWT_SECRET="$REPLY"
ask "OpenAI API key";                                OPENAI_KEY="$REPLY"
ask "OpenAI model" "gpt-4o-mini";                   OPENAI_MODEL="$REPLY"
ask "FACE_MATCH_THRESHOLD (0.0-1.0)" "0.45";         FACE_THRESHOLD="$REPLY"
VSS_HOST=""; VSS_USER="system"; VSS_PW=""; VSS_STOMP_PORT=""; IS_TAILSCALE="false"; TAILSCALE_IP=""
CCTV_COMPOSE=""
if [[ "$CCTV_ENABLED" == "true" ]]; then
    info "VSS (Video Surveillance System) connection details."
    ask "VSS_IP_PORT (host:port)";                   VSS_HOST="$REPLY"
    ask "VSS_USERNAME" "system";                     VSS_USER="$REPLY"
    ask "VSS_PASSWORD";                              VSS_PW="$REPLY"
    ask "VSS_STOMP_PORT" "61615";                    VSS_STOMP_PORT="$REPLY"
    ask_yn "Using Tailscale VPN?" "n";               IS_TAILSCALE="$REPLY"
    if [[ "$IS_TAILSCALE" == "true" ]]; then
        ask "Tailscale IP of this host"; TAILSCALE_IP="$REPLY"
    fi
    CCTV_COMPOSE="cctv"
fi

# ══════════════════════════════════════════════════════════════════════════════
title "STEP 8 — eAssist AI Service"
ask "OpenAI API key for eAssist" "$OPENAI_KEY";      EASSIST_OAI_KEY="$REPLY"
ask "LLM model for eAssist" "gpt-4o-mini";           EASSIST_MODEL="$REPLY"

# ══════════════════════════════════════════════════════════════════════════════
title "Writing .env files"

PREREQ_DIR="${DIR_PREREQ}/prerequisite"

# ── 1. VaultFlow360 / postgres-wal.env ────────────────────────────────────────
if [[ -n "$DIR_VAULT" ]]; then
    BACKUP_DB_PATH="${DIR_VAULT}/backups/data/backup-api.db"
    PG_EXT_LINES="PGPOOL_EXTERNAL_PG_HOST=${PG_EXT_HOST}"$'\n'"PGPOOL_EXTERNAL_PG_PORT=${PG_EXT_PORT:-5432}"
    S3_VAULT_ENDPOINT="$([[ "$IS_ONPREM" == "true" ]] && echo "http://sce-minio:9000" || echo "$S3_ENDPOINT")"
    write_env "${DIR_VAULT}/postgres-wal.env" \
        "# Generated by SCE configure.sh" \
        "POSTGRES_DB=${PG_DB}" \
        "POSTGRES_USER=${PG_USER}" \
        "POSTGRES_PASSWORD=${PG_PASSWORD}" \
        "POSTGRES_SUPERUSER_PASSWORD=${PG_SUPER_PW}" \
        "REPMGR_PASSWORD=${REPMGR_PW}" \
        "PGPOOL_ADMIN_USERNAME=${PGPOOL_USER}" \
        "PGPOOL_ADMIN_PASSWORD=${PGPOOL_PW}" \
        "POSTGRES_HOST_PORT=55432" \
        "POSTGRES_EXPORTER_HOST_PORT=9187" \
        "" \
        "# Backup API" \
        "BACKUP_API_HOST_PORT=8090" \
        "BACKUP_API_PORT=8080" \
        "BACKUP_API_KEY=${BACKUP_KEY}" \
        "PITR_RESTORE_HOST_PORT=55433" \
        "BACKUP_ADMIN_USERNAME=admin" \
        "BACKUP_ADMIN_PASSWORD=${BACKUP_PW}" \
        "BACKUP_API_DB_PATH=${BACKUP_DB_PATH}" \
        "BACKUP_SESSION_TTL_HOURS=24" \
        "BACKUP_COOKIE_SECURE=false" \
        "BACKUP_SCHEDULE_ENABLED=true" \
        "BACKUP_DAILY_TIME=02:00" \
        "BACKUP_TIMEZONE=Asia/Manila" \
        "BACKUP_RETENTION_COUNT=7" \
        "BACKUP_TIMEOUT_MINUTES=120" \
        "BACKUP_WAL_UPLOAD_ENABLED=true" \
        "BACKUP_WAL_UPLOAD_INTERVAL_SECONDS=60" \
        "BACKUP_WAL_UPLOAD_BATCH_SIZE=10" \
        "BACKUP_WAL_UPLOAD_FORCE_SWITCH=false" \
        "BACKUP_POSTGRES_HOST=pg-0" \
        "PGPOOL_EXTERNAL_PG_HOST=${PG_EXT_HOST}" \
        "PGPOOL_EXTERNAL_PG_PORT=${PG_EXT_PORT:-5432}" \
        "BACKUP_POSTGRES_PORT=5432" \
        "BACKUP_LOCAL_DIR=/backups" \
        "BACKUP_WAL_DIR=/wal-archive" \
        "" \
        "# S3 backup storage" \
        "BACKUP_S3_ENABLED=$([[ "$IS_ONPREM" == "true" ]] && echo "true" || echo "false")" \
        "BACKUP_S3_ENDPOINT=${S3_VAULT_ENDPOINT}" \
        "BACKUP_S3_REGION=${S3_REGION}" \
        "BACKUP_S3_BUCKET=${S3_BUCKET}" \
        "BACKUP_S3_PREFIX=${ECOSYSTEM_NAME}-pg-backup" \
        "BACKUP_S3_ACCESS_KEY_ID=${S3_KEY}" \
        "BACKUP_S3_SECRET_ACCESS_KEY=${S3_SECRET}" \
        "BACKUP_S3_FORCE_PATH_STYLE=${S3_FORCE_PATH_STYLE}" \
        "" \
        "OBJECT_BACKUP_ENABLED=false"
fi

# ── 2. SCE-Installation/prerequisite/.env ────────────────────────────────────
if [[ -n "$DIR_PREREQ" ]] && [[ -d "$PREREQ_DIR" ]]; then
    write_env "${PREREQ_DIR}/.env" \
        "# Generated by SCE configure.sh" \
        "REDIS_VERSION=7-alpine" \
        "REDIS_PORT=6379" \
        "REDIS_PASSWORD=${REDIS_PASSWORD}" \
        "" \
        "EMQX_VERSION=5.0.26" \
        "EMQX_MQTT_PORT=1883" \
        "EMQX_WS_PORT=8083" \
        "EMQX_WSS_PORT=2096" \
        "EMQX_MQTTS_PORT=8883" \
        "EMQX_DASHBOARD_PORT=18083" \
        "EMQX_DASHBOARD_USER=admin" \
        "EMQX_DASHBOARD_PASSWORD=${EMQX_DASH_PW}" \
        "" \
        "COMPOSE_PROFILES=$([[ "$IS_ONPREM" == "true" ]] && echo "onprem" || echo "")" \
        "MINIO_VERSION=latest" \
        "MINIO_API_PORT=9010" \
        "MINIO_CONSOLE_PORT=9011" \
        "MINIO_ACCESS_KEY=${S3_KEY}" \
        "MINIO_SECRET_KEY=${S3_SECRET}"
fi

# ── 3. SCE-PHP-SYSTEMS/.env ───────────────────────────────────────────────────
if [[ -n "$DIR_PHP" ]]; then
    S3_PHP_ENDPOINT="$([[ "$IS_ONPREM" == "true" ]] && echo "http://sce-minio:9000" || echo "$S3_ENDPOINT")"
    write_env "${DIR_PHP}/.env" \
        "# Generated by SCE configure.sh" \
        "" \
        "# Database" \
        "DB_HOST=postgres-wal-pgpool" \
        "DB_PORT=5432" \
        "DB_NAME=${PG_DB}" \
        "DB_USER=${PG_USER}" \
        "DB_PASSWORD=${PG_PASSWORD}" \
        "" \
        "# Redis" \
        "REDIS_HOST=sce-redis" \
        "REDIS_PORT=6379" \
        "REDIS_PASSWORD=${REDIS_PASSWORD}" \
        "REDIS_DB=0" \
        "REDIS_PREFIX=" \
        "" \
        "# S3" \
        "S3_ENDPOINT=${S3_PHP_ENDPOINT}" \
        "S3_BUCKET=${S3_BUCKET}" \
        "S3_REGION=${S3_REGION}" \
        "S3_KEY=${S3_KEY}" \
        "S3_SECRET=${S3_SECRET}" \
        "S3_UPLOAD_PATH=${S3_UPLOAD_PATH}" \
        "" \
        "# Mailgun" \
        "MAILGUN_DOMAIN=${MAILGUN_DOMAIN}" \
        "MAILGUN_API_KEY=${MAILGUN_API_KEY}" \
        "MAILGUN_VALIDATION_KEY=${MAILGUN_VAL_KEY}" \
        "" \
        "# Cookies" \
        "COOKIE_NAME_PREFIX=auth_" \
        "COOKIE_PATH=/" \
        "COOKIE_DOMAIN=${COOKIE_DOMAIN}" \
        "COOKIE_SECURE=true" \
        "COOKIE_HTTPONLY=true" \
        "COOKIE_SAMESITE=None" \
        "" \
        "# EMQX / MQTT" \
        "MQ_API_URL=http://sce-emqx:18083" \
        "MQ_API_KEY=${MQ_API_KEY}" \
        "MQ_API_SECRET=${MQ_API_SECRET}" \
        "MQ_WS_URL=ws://sce-emqx:8083/mqtt" \
        "MQ_TOPIC=${MQ_TOPIC}" \
        "" \
        "# System identity" \
        "LGU=${LGU_CODE}" \
        "LGU_NAME=${LGU_NAME}" \
        "HASH_ID_SALT=${HASH_SALT}" \
        "PARTNER_ID=${PARTNER_ID}" \
        "" \
        "# Upload paths" \
        "UPLOAD_TEMP_PATH=/var/www/sce/temp_uploads/" \
        "UPLOAD_TEMP_HREF_PATH=${DOMAIN_URL}/temp_uploads/" \
        "UPLOAD_DEST_PATH=${UPLOAD_DEST_PATH}" \
        "" \
        "# URLs" \
        "QRCODE_BASE_URL=${DOMAIN_URL}/CPA/#/deeplink?data=" \
        "CPA_DOWNLOAD_URL=${DOMAIN_URL}/CPA/download" \
        "CPA_LOGIN_URL=${DOMAIN_URL}/CPA/#/login" \
        "PYTHON_API_URL=http://sce-python-api:8000" \
        "SCE_SETTINGS_API_URL=${DOMAIN_URL}/UAC/api" \
        "" \
        "# Face / KYC" \
        "FACE_COLLECTION=${FACE_COLLECTION}" \
        "" \
        "# EMS" \
        "EMS_APP_NAME=EMS" \
        "EMS_GOOGLE_MAPS_MAP_ID=${GOOGLE_MAPS_ID}" \
        "EMS_FILE_PATH=${EMS_FILE_PATH}" \
        "EMS_SYSTEM_BASE_URL=/EMS" \
        "EMS_LEVEL=${EMS_LEVEL}" \
        "EMS_BOUNDARY_KM=${EMS_BOUNDARY_KM}" \
        "" \
        "# Firebase / Push notifications" \
        "FCM_ENDPOINT=${FCM_ENDPOINT}" \
        "SERVICE_ACCOUNT_PATH=${SERVICE_ACC_PATH}" \
        "APNS_KEY_ID=${APNS_KEY_ID}" \
        "APNS_TEAM_ID=${APNS_TEAM_ID}" \
        "BUNDLE_ID=${BUNDLE_ID}" \
        "KEYPATH=${KEYPATH}" \
        "FIREBASE_VAPID_KEY=${FIREBASE_VAPID}" \
        "" \
        "# WebRTC" \
        "ICE_SERVERS=${ICE_SERVERS}" \
        "" \
        "# CCTV / AI" \
        "CCTV_INTEGRATION_SERVICE=$([[ "$CCTV_ENABLED" == "true" ]] && echo "true" || echo "false")" \
        "EASSIST_PLUGIN=${EASSIST_PLUGIN}" \
        "" \
        "# BullMQ" \
        "BULLMQ_EXPORT_QUEUE=export_records"
fi

# ── 4. SCE-Python-Service/.env ────────────────────────────────────────────────
if [[ -n "$DIR_PYTHON" ]]; then
    S3_PY_ENDPOINT="$([[ "$IS_ONPREM" == "true" ]] && echo "http://sce-minio:9000" || echo "$S3_ENDPOINT")"
    write_env "${DIR_PYTHON}/.env" \
        "# Generated by SCE configure.sh" \
        "" \
        "# Database" \
        "UAC_DB_URL=postgresql://${PG_USER}:${PG_PASSWORD}@postgres-wal-pgpool:5432/${PG_DB}" \
        "IMPORT_DB_URL=postgresql://${PG_USER}:${PG_PASSWORD}@postgres-wal-pgpool:5432/${PG_DB}" \
        "" \
        "# S3" \
        "S3_ENDPOINT_URL=${S3_PY_ENDPOINT}" \
        "S3_ACCESS_KEY=${S3_KEY}" \
        "S3_SECRET_KEY=${S3_SECRET}" \
        "S3_BUCKET_NAME=${S3_BUCKET}" \
        "S3_REGION=${S3_REGION}" \
        "S3_PREFIX=${ECOSYSTEM_NAME}" \
        "" \
        "# Callback" \
        "PHP_CALLBACK_TIMEOUT=30" \
        "PHP_CALLBACK_MAX_RETRIES=3" \
        "PHP_CALLBACK_RETRY_DELAY=5" \
        "" \
        "# Temp dirs" \
        "TMP_DIR=/tmp/pnpki-signer" \
        "UPLOAD_PATH=/tmp/imports" \
        "" \
        "# Redis" \
        "REDIS_HOST=sce-redis" \
        "REDIS_PORT=6379" \
        "REDIS_DB=0" \
        "REDIS_PASSWORD=${REDIS_PASSWORD}" \
        "CACHE_EXPIRE_IN_SECONDS=300" \
        "" \
        "# JWT" \
        "JWT_SECRET_KEY=${JWT_SECRET}" \
        "JWT_ALGORITHM=HS512" \
        "TOKEN_ISSUER=${DOMAIN}" \
        "ACCESS_TOKEN_EXPIRE_MINUTES=43200" \
        "" \
        "# BullMQ" \
        "BULLMQ_FACE_VERIFICATION_QUEUE=kyc_face_verification" \
        "BULLMQ_DOCUMENT_QUEUE=document_processing" \
        "BULLMQ_EXPORT_QUEUE=export_tasks" \
        "BULLMQ_ATTEMPTS=3" \
        "BULLMQ_BACKOFF_TYPE=exponential" \
        "BULLMQ_BACKOFF_DELAY=5000" \
        "BULLMQ_REMOVE_ON_COMPLETE=100" \
        "BULLMQ_REMOVE_ON_FAIL=100" \
        "" \
        "# AI" \
        "AI_PROVIDER=openai" \
        "OPENAI_API_KEY=${OPENAI_KEY}" \
        "OPENAI_MODEL_NAME=${OPENAI_MODEL}" \
        "GEMINI_API_KEY=" \
        "GEMINI_MODEL_NAME=gemini-2.0-flash" \
        "" \
        "# Face verification" \
        "FACE_MATCH_THRESHOLD=${FACE_THRESHOLD}" \
        "FACE_PRIMARY_MODEL=buffalo_l" \
        "KYC_NAME_SIMILARITY_THRESHOLD=0.8" \
        "KYC_ENABLE_STRICT_VALIDATION=true" \
        "KYC_REQUIRE_BOTH_SIDES=false" \
        "" \
        "# EMQX" \
        "EMQX_HOST=http://sce-emqx:18083" \
        "EMQX_PORT=2096" \
        "EMQX_KEY=${MQ_API_KEY}" \
        "EMQX_SECRET=${MQ_API_SECRET}" \
        "EMQX_TOPIC=${MQ_TOPIC}" \
        "" \
        "# CCTV" \
        "CCTV_SERVICE_ENABLED=$([[ "$CCTV_ENABLED" == "true" ]] && echo "true" || echo "false")" \
        "COMPOSE_PROFILES=${CCTV_COMPOSE}" \
        "VSS_IP_PORT=${VSS_HOST}" \
        "VSS_USERNAME=${VSS_USER}" \
        "VSS_PASSWORD=${VSS_PW}" \
        "VSS_STOMP_PORT=${VSS_STOMP_PORT}" \
        "VSS_SUBSCRIBE_TOPICS=mq.event.msg.topic,mq.alarm.msg.topic,mq.common.msg.topic" \
        "VSS_PRIVATE_KEY=" \
        "VSS_PUBLIC_KEY=" \
        "" \
        "# Stream server" \
        "HTTP_SERVER_HOST=http://sce-stream-server:8081" \
        "HTTP_SERVER_PORT=8081" \
        "STREAMS_DIR=/app/streams" \
        "STREAM_ACTIVE_THRESHOLD_S=30" \
        "STREAM_IDLE_TIMEOUT_S=300" \
        "IDLE_CHECK_INTERVAL_S=60" \
        "" \
        "# CCTV worker queues" \
        "TREE_QUEUE_NAME=cctv-device-tree" \
        "STATUS_QUEUE_NAME=cctv-device-status" \
        "CCTV_TREE_INTERVAL_MS=300000" \
        "CCTV_STATUS_INTERVAL_MS=300000" \
        "FAILURE_REQUEUE_DELAY_MS=300000" \
        "DEVICE_INFO_DELAY_S=0.5" \
        "STATUS_BATCH_SIZE=10" \
        "STATUS_BATCH_DELAY_S=0.3" \
        "VSS_REQUEST_TIMEOUT=60" \
        "" \
        "# Network" \
        "IS_TAILSCALE_CONNECT=${IS_TAILSCALE}" \
        "TAILSCALE_IP=${TAILSCALE_IP}"
fi

# ── 5. eAssist-AI-Service/.env ────────────────────────────────────────────────
if [[ -n "$DIR_EASSIST" ]]; then
    write_env "${DIR_EASSIST}/.env" \
        "# Generated by SCE configure.sh" \
        "OPENAI_API_KEY=${EASSIST_OAI_KEY}" \
        "LLM_PROVIDER=openai" \
        "LM_STUDIO_URL=" \
        "LLM_MODEL=${EASSIST_MODEL}" \
        "PORT=3002" \
        "HOST=0.0.0.0" \
        "NODE_ENV=production" \
        "APP_BASE_PATH=" \
        "COPILOTKIT_TELEMETRY_DISABLED=true" \
        "" \
        "SCE_USERNAME=admin" \
        "SCE_PASSWORD=" \
        "SCE_APP_TYPE=ITBS" \
        "" \
        "CRMS_DATA_SOURCE=api" \
        "CRMS_API_BASE_URL=http://sce-php-app/CRMS" \
        "CRMS_DEBUG=false" \
        "" \
        "EMS_DATA_SOURCE=api" \
        "EMS_API_BASE_URL=http://sce-php-app/EMS" \
        "EMS_DEBUG=false"
fi

# ── Ask to start Docker ───────────────────────────────────────────────────────
ask_yn "Start all Docker stacks now?" "y"
START_DOCKER="$REPLY"
fi  # end of skip_config block

# ══════════════════════════════════════════════════════════════════════════════
title "Starting Docker Stacks"

run_stack() {
    local name="$1" dir="$2" cmd="${3:-docker compose up -d --build}"
    if [[ -z "$dir" ]] || [[ ! -d "$dir" ]]; then
        warn "Skipping ${name} — directory not found."
        return
    fi
    log "Starting: ${name}"
    dim "  cd ${dir}"
    dim "  ${cmd}"
    if (cd "$dir" && eval "$cmd"); then
        ok "${name} started."
    else
        err "Failed to start ${name}. Check errors above."
    fi
    sleep 2
}

if [[ "$START_DOCKER" == "true" ]]; then
    run_stack "VaultFlow360 (PostgreSQL HA)"       "$DIR_VAULT"                  "docker compose --env-file postgres-wal.env up -d --build"
    run_stack "Prerequisites (Redis/EMQX/MinIO)"   "${DIR_PREREQ}/prerequisite"  "docker compose up -d"
    run_stack "SCE-PHP-SYSTEMS"                    "$DIR_PHP"                    "docker compose up -d --build"
    run_stack "SCE-Python-Service"                 "$DIR_PYTHON"                 "docker compose up -d --build"
    run_stack "eAssist-AI-Service"                 "$DIR_EASSIST"                "docker compose up -d --build"
else
    info "Skipped Docker start. Run stacks manually in this order:"
    [[ -n "$DIR_VAULT"   ]] && dim "cd \"${DIR_VAULT}\" && docker compose --env-file postgres-wal.env up -d --build"
    [[ -n "$DIR_PREREQ"  ]] && dim "cd \"${DIR_PREREQ}/prerequisite\" && docker compose up -d"
    [[ -n "$DIR_PHP"     ]] && dim "cd \"${DIR_PHP}\" && docker compose up -d --build"
    [[ -n "$DIR_PYTHON"  ]] && dim "cd \"${DIR_PYTHON}\" && docker compose up -d --build"
    [[ -n "$DIR_EASSIST" ]] && dim "cd \"${DIR_EASSIST}\" && docker compose up -d --build"
fi

# ══════════════════════════════════════════════════════════════════════════════
title "DONE — Post-install checklist"
echo -e "${BOLD}Complete these steps after containers are healthy:${RESET}"
echo ""
echo "  1. EMQX API key — open http://localhost:18083 → System → API Keys"
echo "     Update MQ_API_KEY/MQ_API_SECRET in PHP + Python .env, then restart."
[[ "${IS_ONPREM:-false}" == "true" ]] && \
echo "  2. MinIO bucket — open http://localhost:9011 → Create bucket: ${S3_BUCKET:-<your-bucket>}"
echo "  3. PHP database installer — open https://${DOMAIN:-your-domain}/UAC/install"
echo "  4. Copy firebase-service-account.json into sce-php-app container"
echo "  5. Copy APNs .p8 key into sce-php-app container"
echo "  6. Set SCE_PASSWORD in eAssist-AI-Service/.env, then restart"
[[ "${CCTV_ENABLED:-false}" == "true" ]] && \
echo "  7. Add VSS_PRIVATE_KEY and VSS_PUBLIC_KEY to SCE-Python-Service/.env"
echo ""
echo -e "${GREEN}${BOLD}All done!${RESET}"
