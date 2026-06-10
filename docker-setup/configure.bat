@echo off
setlocal EnableDelayedExpansion
title SCE Ecosystem — Docker Environment Setup

echo.
echo ================================================================
echo  SCE Ecosystem -- Docker Environment Setup Wizard
echo ================================================================
echo  Scans sibling repos, collects credentials, writes all .env
echo  files, and starts Docker stacks in the correct order.
echo ================================================================
echo.

:: ── Resolve ecosystem root (two levels up from this script) ──────────────────
set "SCRIPT_DIR=%~dp0"
for %%A in ("%SCRIPT_DIR%..\..") do set "ROOT=%%~fA"
for %%A in ("%ROOT%") do set "ECOSYSTEM_NAME=%%~nxA"
echo  Ecosystem root: %ROOT%
echo.

:: ── Discover repos by keyword ─────────────────────────────────────────────────
set "DIR_VAULT="
set "DIR_PREREQ="
set "DIR_PHP="
set "DIR_PYTHON="
set "DIR_EASSIST="

for /D %%D in ("%ROOT%\*") do (
    set "_n=%%~nxD"
    set "_nl=!_n!"
    call :to_lower _nl

    echo !_nl! | findstr /i "vault"        >nul 2>&1 && if not defined DIR_VAULT   set "DIR_VAULT=%%D"
    echo !_nl! | findstr /i "installation" >nul 2>&1 && if not defined DIR_PREREQ  set "DIR_PREREQ=%%D"
    echo !_nl! | findstr /i "php"          >nul 2>&1 && if not defined DIR_PHP     set "DIR_PHP=%%D"
    echo !_nl! | findstr /i "python"       >nul 2>&1 && if not defined DIR_PYTHON  set "DIR_PYTHON=%%D"
    echo !_nl! | findstr /i "eassist"      >nul 2>&1 && if not defined DIR_EASSIST set "DIR_EASSIST=%%D"
)

echo  Scanning for repositories...
echo.
call :resolve_repo DIR_VAULT   "VaultFlow360        (PostgreSQL HA)"       "!DIR_VAULT!"
call :resolve_repo DIR_PREREQ  "SCE-Installation    (This installer repo)" "!DIR_PREREQ!"
call :resolve_repo DIR_PHP     "SCE-PHP-SYSTEMS     (PHP web app)"         "!DIR_PHP!"
call :resolve_repo DIR_PYTHON  "SCE-Python-Service  (FastAPI + workers)"   "!DIR_PYTHON!"
call :resolve_repo DIR_EASSIST "eAssist-AI-Service  (AI assistant)"        "!DIR_EASSIST!"
echo.

:: ── Already configured? ───────────────────────────────────────────────────────
echo ----------------------------------------------------------------
set /p "_skip=Already configured .env files -- just (re)start Docker? [y/N]: "
if /i "!_skip!"=="y" goto :start_docker

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 1 -- Deployment Type
echo ================================================================
set /p "_onprem=Is this an ON-PREM deployment? (MinIO instead of cloud S3) [y/N]: "
set "IS_ONPREM=false"
if /i "!_onprem!"=="y" set "IS_ONPREM=true"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 2 -- Domain and Identity
echo ================================================================
echo  Info: Enter your public domain, or press Enter for localhost (local development).
set "DOMAIN=localhost"
set /p "DOMAIN=System domain [localhost]: "
if "!DOMAIN!"=="" set "DOMAIN=localhost"
set "DOMAIN_URL=https://!DOMAIN!"
if "!DOMAIN!"=="localhost" set "DOMAIN_URL=http://localhost"
echo !DOMAIN! | findstr /b "localhost:" >nul 2>&1 && set "DOMAIN_URL=http://!DOMAIN!"

:: Simple slugify: replace spaces/underscores/dots with hyphens, lowercase
set "_slug=!ECOSYSTEM_NAME!"
set "_slug=!_slug: =-!"
set "_slug=!_slug:_=-!"
set "_slug=!_slug:.=-!"
call :to_lower _slug

set /p "_lgu_code=LGU code [!_slug!]: "
if "!_lgu_code!"=="" set "_lgu_code=!_slug!"
set "LGU_CODE=!_lgu_code!"

set "_lgu_name_default=!ECOSYSTEM_NAME:-= !"
set /p "_lgu_name=LGU full name [!_lgu_name_default!]: "
if "!_lgu_name!"=="" set "_lgu_name=!_lgu_name_default!"
set "LGU_NAME=!_lgu_name!"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 3 -- Database (VaultFlow360 / PostgreSQL)
echo ================================================================
echo  Info: Name of the PostgreSQL database the app will use.
set /p "PG_DB=PostgreSQL database name [sce_db]: " & if "!PG_DB!"=="" set "PG_DB=sce_db"
set /p "PG_USER=PostgreSQL app username [appuser]: " & if "!PG_USER!"=="" set "PG_USER=appuser"
call :rand16 _r2
set /p "PG_PASSWORD=PostgreSQL app password [!_r2!]: " & if "!PG_PASSWORD!"=="" set "PG_PASSWORD=!_r2!"
call :rand16 _r3
set /p "PG_SUPER_PW=PostgreSQL superuser password [!_r3!]: " & if "!PG_SUPER_PW!"=="" set "PG_SUPER_PW=!_r3!"
call :rand16 _r4
set /p "REPMGR_PW=Repmgr password [!_r4!]: " & if "!REPMGR_PW!"=="" set "REPMGR_PW=!_r4!"
set /p "PGPOOL_USER=Pgpool admin username [admin]: " & if "!PGPOOL_USER!"=="" set "PGPOOL_USER=admin"
call :rand16 _r5
set /p "PGPOOL_PW=Pgpool admin password [!_r5!]: " & if "!PGPOOL_PW!"=="" set "PGPOOL_PW=!_r5!"
call :rand16 _r6
set /p "BACKUP_PW=Backup API admin password [!_r6!]: " & if "!BACKUP_PW!"=="" set "BACKUP_PW=!_r6!"
call :rand16 _r7
set /p "BACKUP_KEY=Backup API key [!_r7!]: " & if "!BACKUP_KEY!"=="" set "BACKUP_KEY=!_r7!"
echo  Info: Leave PGPOOL_EXTERNAL_PG_HOST blank if no external Postgres replica
set /p "PG_EXT_HOST=PGPOOL_EXTERNAL_PG_HOST: "
set "PG_EXT_PORT="
if not "!PG_EXT_HOST!"=="" set /p "PG_EXT_PORT=PGPOOL_EXTERNAL_PG_PORT [5432]: " & if "!PG_EXT_PORT!"=="" set "PG_EXT_PORT=5432"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 4 -- Redis and EMQX
echo ================================================================
call :rand16 _r8
set /p "REDIS_PASSWORD=Redis password [!_r8!]: " & if "!REDIS_PASSWORD!"=="" set "REDIS_PASSWORD=!_r8!"
call :rand16 _r9
set /p "EMQX_DASH_PW=EMQX dashboard password [!_r9!]: " & if "!EMQX_DASH_PW!"=="" set "EMQX_DASH_PW=!_r9!"
echo  Info: EMQX API key/secret are created after first boot in the EMQX dashboard.
set /p "MQ_API_KEY=EMQX API key (leave blank for now): "
set /p "MQ_API_SECRET=EMQX API secret (leave blank for now): "
set /p "_mq_topic=MQTT topic [!LGU_CODE!]: " & if "!_mq_topic!"=="" set "_mq_topic=!LGU_CODE!"
set "MQ_TOPIC=!_mq_topic!"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 5 -- S3 / Object Storage
echo ================================================================
if "!IS_ONPREM!"=="true" (
    echo  Info: On-prem -- MinIO container hostname is sce-minio
    set "S3_ENDPOINT=http://sce-minio:9000"
    set /p "S3_BUCKET=MinIO bucket name [!LGU_CODE!]: " & if "!S3_BUCKET!"=="" set "S3_BUCKET=!LGU_CODE!"
    set "S3_REGION=us-east-1"
    set /p "S3_KEY=MinIO access key [minioadmin]: " & if "!S3_KEY!"=="" set "S3_KEY=minioadmin"
    call :rand16 _r10
    set /p "S3_SECRET=MinIO secret key [!_r10!]: " & if "!S3_SECRET!"=="" set "S3_SECRET=!_r10!"
    set "S3_FORCE_PATH=true"
) else (
    set /p "S3_ENDPOINT=S3 endpoint URL (e.g. https://sgp1.digitaloceanspaces.com): "
    set /p "S3_BUCKET=S3 bucket name: "
    set /p "S3_REGION=S3 region [sgp1]: " & if "!S3_REGION!"=="" set "S3_REGION=sgp1"
    set /p "S3_KEY=S3 access key: "
    set /p "S3_SECRET=S3 secret key: "
    set "S3_FORCE_PATH=false"
)
set /p "S3_UPLOAD_PATH=S3 prefix for uploads [!ECOSYSTEM_NAME!/uploads/]: "
if "!S3_UPLOAD_PATH!"=="" set "S3_UPLOAD_PATH=!ECOSYSTEM_NAME!/uploads/"
set /p "EMS_FILE_PATH=S3 prefix for EMS files [!ECOSYSTEM_NAME!/incident/]: "
if "!EMS_FILE_PATH!"=="" set "EMS_FILE_PATH=!ECOSYSTEM_NAME!/incident/"
set /p "UPLOAD_DEST_PATH=S3 prefix for final uploads [!ECOSYSTEM_NAME!/dest/]: "
if "!UPLOAD_DEST_PATH!"=="" set "UPLOAD_DEST_PATH=!ECOSYSTEM_NAME!/dest/"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 6 -- PHP App Settings
echo ================================================================
call :rand16 _rs
set /p "HASH_SALT=HASH_ID_SALT [!_rs!]: " & if "!HASH_SALT!"=="" set "HASH_SALT=!_rs!"
set /p "FACE_COLLECTION=AWS Rekognition FACE_COLLECTION name: "
echo  Info: COOKIE_DOMAIN is the domain where browsers send auth cookies.
set /p "COOKIE_DOMAIN=COOKIE_DOMAIN [!DOMAIN!]: " & if "!COOKIE_DOMAIN!"=="" set "COOKIE_DOMAIN=!DOMAIN!"
set /p "MAILGUN_DOMAIN=Mailgun domain: "
set /p "MAILGUN_API_KEY=Mailgun API key: "
set /p "MAILGUN_VAL_KEY=Mailgun validation key: "
set /p "FIREBASE_VAPID=FIREBASE_VAPID_KEY: "
set /p "FCM_ENDPOINT=FCM_ENDPOINT: "
:: Container paths — fixed, never ask
set "SERVICE_ACC_PATH=/var/www/sce/firebase-service-account.json"
set "KEYPATH=/var/www/sce/apns.p8"
set /p "APNS_KEY_ID=APNS_KEY_ID: "
set /p "APNS_TEAM_ID=APNS_TEAM_ID: "
set /p "BUNDLE_ID=BUNDLE_ID (iOS bundle ID): "
set /p "ICE_SERVERS=ICE_SERVERS [{"urls":["stun:stun.l.google.com:19302"]}]: "
if "!ICE_SERVERS!"=="" set "ICE_SERVERS=[{\"urls\":[\"stun:stun.l.google.com:19302\"]}]"
set /p "_cctv=Enable CCTV integration? [y/N]: "
set "CCTV_ENABLED=false"
if /i "!_cctv!"=="y" set "CCTV_ENABLED=true"
:: EASSIST_PLUGIN — URL of the eAssist dist-plugin build (not a file path)
set /p "EASSIST_PLUGIN=EASSIST_PLUGIN URL [!DOMAIN_URL!/eassist/dist-plugin]: "
if "!EASSIST_PLUGIN!"=="" set "EASSIST_PLUGIN=!DOMAIN_URL!/eassist/dist-plugin"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 7 -- Python Service Settings
echo ================================================================
call :rand32 _rj
set /p "JWT_SECRET=JWT_SECRET_KEY [!_rj!]: " & if "!JWT_SECRET!"=="" set "JWT_SECRET=!_rj!"
set /p "OPENAI_KEY=OpenAI API key: "
set /p "OPENAI_MODEL=OpenAI model [gpt-4o-mini]: " & if "!OPENAI_MODEL!"=="" set "OPENAI_MODEL=gpt-4o-mini"
set /p "FACE_THRESHOLD=FACE_MATCH_THRESHOLD [0.45]: " & if "!FACE_THRESHOLD!"=="" set "FACE_THRESHOLD=0.45"
set "VSS_HOST=" & set "VSS_USER=system" & set "VSS_PW=" & set "VSS_STOMP_PORT="
set "IS_TAILSCALE=false" & set "TAILSCALE_IP=" & set "CCTV_COMPOSE="
if "!CCTV_ENABLED!"=="true" (
    set /p "VSS_HOST=VSS_IP_PORT (host:port): "
    set /p "VSS_USER=VSS_USERNAME [system]: " & if "!VSS_USER!"=="" set "VSS_USER=system"
    set /p "VSS_PW=VSS_PASSWORD: "
    set /p "VSS_STOMP_PORT=VSS_STOMP_PORT [61615]: " & if "!VSS_STOMP_PORT!"=="" set "VSS_STOMP_PORT=61615"
    set /p "_ts=Using Tailscale VPN? [y/N]: "
    if /i "!_ts!"=="y" ( set "IS_TAILSCALE=true" & set /p "TAILSCALE_IP=Tailscale IP: " )
    set "CCTV_COMPOSE=cctv"
)

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  STEP 8 -- eAssist AI Service
echo ================================================================
set /p "EASSIST_OAI_KEY=OpenAI API key for eAssist [same as Python]: "
if "!EASSIST_OAI_KEY!"=="" set "EASSIST_OAI_KEY=!OPENAI_KEY!"
set /p "EASSIST_MODEL=LLM model for eAssist [gpt-4o-mini]: "
if "!EASSIST_MODEL!"=="" set "EASSIST_MODEL=gpt-4o-mini"

:: ══════════════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  Writing .env files
echo ================================================================

:: ── 1. VaultFlow360 ───────────────────────────────────────────────────────────
if defined DIR_VAULT (
    set "_f=!DIR_VAULT!\postgres-wal.env"
    set "_s3v=!S3_ENDPOINT!"
    if "!IS_ONPREM!"=="true" set "_s3v=http://sce-minio:9000"
    (
        echo # Generated by SCE configure.bat
        echo POSTGRES_DB=!PG_DB!
        echo POSTGRES_USER=!PG_USER!
        echo POSTGRES_PASSWORD=!PG_PASSWORD!
        echo POSTGRES_SUPERUSER_PASSWORD=!PG_SUPER_PW!
        echo REPMGR_PASSWORD=!REPMGR_PW!
        echo PGPOOL_ADMIN_USERNAME=!PGPOOL_USER!
        echo PGPOOL_ADMIN_PASSWORD=!PGPOOL_PW!
        echo POSTGRES_HOST_PORT=55432
        echo POSTGRES_EXPORTER_HOST_PORT=9187
        echo.
        echo # Backup API
        echo BACKUP_API_HOST_PORT=8090
        echo BACKUP_API_PORT=8080
        echo BACKUP_API_KEY=!BACKUP_KEY!
        echo PITR_RESTORE_HOST_PORT=55433
        echo BACKUP_ADMIN_USERNAME=admin
        echo BACKUP_ADMIN_PASSWORD=!BACKUP_PW!
        echo BACKUP_API_DB_PATH=!DIR_VAULT!\backups\data\backup-api.db
        echo BACKUP_SESSION_TTL_HOURS=24
        echo BACKUP_COOKIE_SECURE=false
        echo BACKUP_SCHEDULE_ENABLED=true
        echo BACKUP_DAILY_TIME=02:00
        echo BACKUP_TIMEZONE=Asia/Manila
        echo BACKUP_RETENTION_COUNT=7
        echo BACKUP_TIMEOUT_MINUTES=120
        echo BACKUP_WAL_UPLOAD_ENABLED=true
        echo BACKUP_WAL_UPLOAD_INTERVAL_SECONDS=60
        echo BACKUP_WAL_UPLOAD_BATCH_SIZE=10
        echo BACKUP_WAL_UPLOAD_FORCE_SWITCH=false
        echo BACKUP_POSTGRES_HOST=pg-0
        echo PGPOOL_EXTERNAL_PG_HOST=!PG_EXT_HOST!
        echo PGPOOL_EXTERNAL_PG_PORT=!PG_EXT_PORT!
        echo BACKUP_POSTGRES_PORT=5432
        echo BACKUP_LOCAL_DIR=/backups
        echo BACKUP_WAL_DIR=/wal-archive
        echo.
        echo # S3 backup storage
        if "!IS_ONPREM!"=="true" ( echo BACKUP_S3_ENABLED=true ) else ( echo BACKUP_S3_ENABLED=false )
        echo BACKUP_S3_ENDPOINT=!_s3v!
        echo BACKUP_S3_REGION=!S3_REGION!
        echo BACKUP_S3_BUCKET=!S3_BUCKET!
        echo BACKUP_S3_PREFIX=!ECOSYSTEM_NAME!-pg-backup
        echo BACKUP_S3_ACCESS_KEY_ID=!S3_KEY!
        echo BACKUP_S3_SECRET_ACCESS_KEY=!S3_SECRET!
        echo BACKUP_S3_FORCE_PATH_STYLE=!S3_FORCE_PATH!
        echo.
        echo OBJECT_BACKUP_ENABLED=false
    ) > "!_f!"
    echo   [OK] Written: !_f!
)

:: ── 2. SCE-Installation/prerequisite/.env ────────────────────────────────────
if defined DIR_PREREQ (
    set "_pdir=!DIR_PREREQ!\prerequisite"
    if exist "!_pdir!" (
        set "_f=!_pdir!\.env"
        set "_cp="
        if "!IS_ONPREM!"=="true" set "_cp=onprem"
        (
            echo # Generated by SCE configure.bat
            echo REDIS_VERSION=7-alpine
            echo REDIS_PORT=6379
            echo REDIS_PASSWORD=!REDIS_PASSWORD!
            echo.
            echo EMQX_VERSION=5.0.26
            echo EMQX_MQTT_PORT=1883
            echo EMQX_WS_PORT=8083
            echo EMQX_WSS_PORT=2096
            echo EMQX_MQTTS_PORT=8883
            echo EMQX_DASHBOARD_PORT=18083
            echo EMQX_DASHBOARD_USER=admin
            echo EMQX_DASHBOARD_PASSWORD=!EMQX_DASH_PW!
            echo.
            echo COMPOSE_PROFILES=!_cp!
            echo MINIO_VERSION=latest
            echo MINIO_API_PORT=9010
            echo MINIO_CONSOLE_PORT=9011
            echo MINIO_ACCESS_KEY=!S3_KEY!
            echo MINIO_SECRET_KEY=!S3_SECRET!
        ) > "!_f!"
        echo   [OK] Written: !_f!
    )
)

:: ── 3. SCE-PHP-SYSTEMS/.env ───────────────────────────────────────────────────
if defined DIR_PHP (
    set "_f=!DIR_PHP!\.env"
    set "_s3p=!S3_ENDPOINT!"
    if "!IS_ONPREM!"=="true" set "_s3p=http://sce-minio:9000"
    (
        echo # Generated by SCE configure.bat
        echo.
        echo # Database
        echo DB_HOST=postgres-wal-pgpool
        echo DB_PORT=5432
        echo DB_NAME=!PG_DB!
        echo DB_USER=!PG_USER!
        echo DB_PASSWORD=!PG_PASSWORD!
        echo.
        echo # Redis
        echo REDIS_HOST=sce-redis
        echo REDIS_PORT=6379
        echo REDIS_PASSWORD=!REDIS_PASSWORD!
        echo REDIS_DB=0
        echo REDIS_PREFIX=
        echo.
        echo # S3
        echo S3_ENDPOINT=!_s3p!
        echo S3_BUCKET=!S3_BUCKET!
        echo S3_REGION=!S3_REGION!
        echo S3_KEY=!S3_KEY!
        echo S3_SECRET=!S3_SECRET!
        echo S3_UPLOAD_PATH=!S3_UPLOAD_PATH!
        echo.
        echo # Mailgun
        echo MAILGUN_DOMAIN=!MAILGUN_DOMAIN!
        echo MAILGUN_API_KEY=!MAILGUN_API_KEY!
        echo MAILGUN_VALIDATION_KEY=!MAILGUN_VAL_KEY!
        echo.
        echo # Cookies
        echo COOKIE_NAME_PREFIX=auth_
        echo COOKIE_PATH=/
        echo COOKIE_DOMAIN=!COOKIE_DOMAIN!
        echo COOKIE_SECURE=true
        echo COOKIE_HTTPONLY=true
        echo COOKIE_SAMESITE=None
        echo.
        echo # EMQX / MQTT
        echo MQ_API_URL=http://sce-emqx:18083
        echo MQ_API_KEY=!MQ_API_KEY!
        echo MQ_API_SECRET=!MQ_API_SECRET!
        echo MQ_WS_URL=ws://sce-emqx:8083/mqtt
        echo MQ_TOPIC=!MQ_TOPIC!
        echo.
        echo # System identity
        echo LGU=!LGU_CODE!
        echo LGU_NAME=!LGU_NAME!
        echo HASH_ID_SALT=!HASH_SALT!
        echo PARTNER_ID=1
        echo.
        echo # Upload paths
        echo UPLOAD_TEMP_PATH=/var/www/sce/temp_uploads/
        echo UPLOAD_TEMP_HREF_PATH=!DOMAIN_URL!/temp_uploads/
        echo UPLOAD_DEST_PATH=!UPLOAD_DEST_PATH!
        echo.
        echo # URLs
        echo QRCODE_BASE_URL=!DOMAIN_URL!/CPA/#/deeplink?data=
        echo CPA_DOWNLOAD_URL=!DOMAIN_URL!/CPA/download
        echo CPA_LOGIN_URL=!DOMAIN_URL!/CPA/#/login
        echo PYTHON_API_URL=http://sce-python-api:8000
        echo SCE_SETTINGS_API_URL=!DOMAIN_URL!/UAC/api
        echo.
        echo # Face / KYC
        echo FACE_COLLECTION=!FACE_COLLECTION!
        echo.
        echo # EMS
        echo EMS_APP_NAME=EMS
        echo EMS_GOOGLE_MAPS_MAP_ID=
        echo EMS_FILE_PATH=!EMS_FILE_PATH!
        echo EMS_SYSTEM_BASE_URL=/EMS
        echo EMS_LEVEL=1
        echo EMS_BOUNDARY_KM=10
        echo.
        echo # Firebase / Push notifications
        echo FCM_ENDPOINT=!FCM_ENDPOINT!
        echo SERVICE_ACCOUNT_PATH=!SERVICE_ACC_PATH!
        echo APNS_KEY_ID=!APNS_KEY_ID!
        echo APNS_TEAM_ID=!APNS_TEAM_ID!
        echo BUNDLE_ID=!BUNDLE_ID!
        echo KEYPATH=!KEYPATH!
        echo FIREBASE_VAPID_KEY=!FIREBASE_VAPID!
        echo.
        echo # WebRTC
        echo ICE_SERVERS=!ICE_SERVERS!
        echo.
        echo # CCTV / AI
        echo CCTV_INTEGRATION_SERVICE=!CCTV_ENABLED!
        echo EASSIST_PLUGIN=!EASSIST_PLUGIN!
        echo.
        echo # BullMQ
        echo BULLMQ_EXPORT_QUEUE=export_records
    ) > "!_f!"
    echo   [OK] Written: !_f!
)

:: ── 4. SCE-Python-Service/.env ────────────────────────────────────────────────
if defined DIR_PYTHON (
    set "_f=!DIR_PYTHON!\.env"
    set "_s3py=!S3_ENDPOINT!"
    if "!IS_ONPREM!"=="true" set "_s3py=http://sce-minio:9000"
    (
        echo # Generated by SCE configure.bat
        echo.
        echo # Database
        echo UAC_DB_URL=postgresql://!PG_USER!:!PG_PASSWORD!@postgres-wal-pgpool:5432/!PG_DB!
        echo IMPORT_DB_URL=postgresql://!PG_USER!:!PG_PASSWORD!@postgres-wal-pgpool:5432/!PG_DB!
        echo.
        echo # S3
        echo S3_ENDPOINT_URL=!_s3py!
        echo S3_ACCESS_KEY=!S3_KEY!
        echo S3_SECRET_KEY=!S3_SECRET!
        echo S3_BUCKET_NAME=!S3_BUCKET!
        echo S3_REGION=!S3_REGION!
        echo S3_PREFIX=!ECOSYSTEM_NAME!
        echo.
        echo # Callback
        echo PHP_CALLBACK_TIMEOUT=30
        echo PHP_CALLBACK_MAX_RETRIES=3
        echo PHP_CALLBACK_RETRY_DELAY=5
        echo.
        echo # Temp dirs
        echo TMP_DIR=/tmp/pnpki-signer
        echo UPLOAD_PATH=/tmp/imports
        echo.
        echo # Redis
        echo REDIS_HOST=sce-redis
        echo REDIS_PORT=6379
        echo REDIS_DB=0
        echo REDIS_PASSWORD=!REDIS_PASSWORD!
        echo CACHE_EXPIRE_IN_SECONDS=300
        echo.
        echo # JWT
        echo JWT_SECRET_KEY=!JWT_SECRET!
        echo JWT_ALGORITHM=HS512
        echo TOKEN_ISSUER=!DOMAIN!
        echo ACCESS_TOKEN_EXPIRE_MINUTES=43200
        echo.
        echo # BullMQ
        echo BULLMQ_FACE_VERIFICATION_QUEUE=kyc_face_verification
        echo BULLMQ_DOCUMENT_QUEUE=document_processing
        echo BULLMQ_EXPORT_QUEUE=export_tasks
        echo BULLMQ_ATTEMPTS=3
        echo BULLMQ_BACKOFF_TYPE=exponential
        echo BULLMQ_BACKOFF_DELAY=5000
        echo BULLMQ_REMOVE_ON_COMPLETE=100
        echo BULLMQ_REMOVE_ON_FAIL=100
        echo.
        echo # AI
        echo AI_PROVIDER=openai
        echo OPENAI_API_KEY=!OPENAI_KEY!
        echo OPENAI_MODEL_NAME=!OPENAI_MODEL!
        echo GEMINI_API_KEY=
        echo GEMINI_MODEL_NAME=gemini-2.0-flash
        echo.
        echo # Face verification
        echo FACE_MATCH_THRESHOLD=!FACE_THRESHOLD!
        echo FACE_PRIMARY_MODEL=buffalo_l
        echo KYC_NAME_SIMILARITY_THRESHOLD=0.8
        echo KYC_ENABLE_STRICT_VALIDATION=true
        echo KYC_REQUIRE_BOTH_SIDES=false
        echo.
        echo # EMQX
        echo EMQX_HOST=http://sce-emqx:18083
        echo EMQX_PORT=2096
        echo EMQX_KEY=!MQ_API_KEY!
        echo EMQX_SECRET=!MQ_API_SECRET!
        echo EMQX_TOPIC=!MQ_TOPIC!
        echo.
        echo # CCTV
        echo CCTV_SERVICE_ENABLED=!CCTV_ENABLED!
        echo COMPOSE_PROFILES=!CCTV_COMPOSE!
        echo VSS_IP_PORT=!VSS_HOST!
        echo VSS_USERNAME=!VSS_USER!
        echo VSS_PASSWORD=!VSS_PW!
        echo VSS_STOMP_PORT=!VSS_STOMP_PORT!
        echo VSS_SUBSCRIBE_TOPICS=mq.event.msg.topic,mq.alarm.msg.topic,mq.common.msg.topic
        echo VSS_PRIVATE_KEY=
        echo VSS_PUBLIC_KEY=
        echo.
        echo # Stream server
        echo HTTP_SERVER_HOST=http://sce-stream-server:8081
        echo HTTP_SERVER_PORT=8081
        echo STREAMS_DIR=/app/streams
        echo STREAM_ACTIVE_THRESHOLD_S=30
        echo STREAM_IDLE_TIMEOUT_S=300
        echo IDLE_CHECK_INTERVAL_S=60
        echo.
        echo # CCTV worker queues
        echo TREE_QUEUE_NAME=cctv-device-tree
        echo STATUS_QUEUE_NAME=cctv-device-status
        echo CCTV_TREE_INTERVAL_MS=300000
        echo CCTV_STATUS_INTERVAL_MS=300000
        echo FAILURE_REQUEUE_DELAY_MS=300000
        echo DEVICE_INFO_DELAY_S=0.5
        echo STATUS_BATCH_SIZE=10
        echo STATUS_BATCH_DELAY_S=0.3
        echo VSS_REQUEST_TIMEOUT=60
        echo.
        echo # Network
        echo IS_TAILSCALE_CONNECT=!IS_TAILSCALE!
        echo TAILSCALE_IP=!TAILSCALE_IP!
    ) > "!_f!"
    echo   [OK] Written: !_f!
)

:: ── 5. eAssist-AI-Service/.env ────────────────────────────────────────────────
if defined DIR_EASSIST (
    set "_f=!DIR_EASSIST!\.env"
    (
        echo # Generated by SCE configure.bat
        echo OPENAI_API_KEY=!EASSIST_OAI_KEY!
        echo LLM_PROVIDER=openai
        echo LM_STUDIO_URL=
        echo LLM_MODEL=!EASSIST_MODEL!
        echo PORT=3002
        echo HOST=0.0.0.0
        echo NODE_ENV=production
        echo APP_BASE_PATH=
        echo COPILOTKIT_TELEMETRY_DISABLED=true
        echo.
        echo SCE_USERNAME=admin
        echo SCE_PASSWORD=
        echo SCE_APP_TYPE=ITBS
        echo.
        echo CRMS_DATA_SOURCE=api
        echo CRMS_API_BASE_URL=http://sce-php-app/CRMS
        echo CRMS_DEBUG=false
        echo.
        echo EMS_DATA_SOURCE=api
        echo EMS_API_BASE_URL=http://sce-php-app/EMS
        echo EMS_DEBUG=false
    ) > "!_f!"
    echo   [OK] Written: !_f!
)

echo.
set /p "_start=Start all Docker stacks now? [Y/n]: "
if /i "!_start!"=="n" goto :skip_start

:start_docker
echo.
echo ================================================================
echo  Starting Docker Stacks
echo ================================================================

if defined DIR_VAULT (
    echo.
    echo -- VaultFlow360 (PostgreSQL HA^)
    cd /d "!DIR_VAULT!" && docker compose --env-file postgres-wal.env up -d --build
    if errorlevel 1 ( echo [ERROR] VaultFlow360 failed ) else ( echo [OK] VaultFlow360 started )
    timeout /t 3 /nobreak >nul
)
if defined DIR_PREREQ (
    echo.
    echo -- Prerequisites (Redis/EMQX/MinIO^)
    cd /d "!DIR_PREREQ!\prerequisite" && docker compose up -d
    if errorlevel 1 ( echo [ERROR] Prerequisites failed ) else ( echo [OK] Prerequisites started )
    timeout /t 3 /nobreak >nul
)
if defined DIR_PHP (
    echo.
    echo -- SCE-PHP-SYSTEMS
    cd /d "!DIR_PHP!" && docker compose up -d --build
    if errorlevel 1 ( echo [ERROR] SCE-PHP-SYSTEMS failed ) else ( echo [OK] SCE-PHP-SYSTEMS started )
    timeout /t 2 /nobreak >nul
)
if defined DIR_PYTHON (
    echo.
    echo -- SCE-Python-Service
    cd /d "!DIR_PYTHON!" && docker compose up -d --build
    if errorlevel 1 ( echo [ERROR] SCE-Python-Service failed ) else ( echo [OK] SCE-Python-Service started )
    timeout /t 2 /nobreak >nul
)
if defined DIR_EASSIST (
    echo.
    echo -- eAssist-AI-Service
    cd /d "!DIR_EASSIST!" && docker compose up -d --build
    if errorlevel 1 ( echo [ERROR] eAssist failed ) else ( echo [OK] eAssist started )
)
goto :done

:skip_start
echo.
echo  Skipped Docker start. Run stacks manually in this order:
if defined DIR_VAULT   echo   cd "!DIR_VAULT!" ^&^& docker compose --env-file postgres-wal.env up -d --build
if defined DIR_PREREQ  echo   cd "!DIR_PREREQ!\prerequisite" ^&^& docker compose up -d
if defined DIR_PHP     echo   cd "!DIR_PHP!" ^&^& docker compose up -d --build
if defined DIR_PYTHON  echo   cd "!DIR_PYTHON!" ^&^& docker compose up -d --build
if defined DIR_EASSIST echo   cd "!DIR_EASSIST!" ^&^& docker compose up -d --build

:done
echo.
echo ================================================================
echo  DONE -- Post-install checklist
echo ================================================================
echo  1. EMQX API key -- open http://localhost:18083 ^> System ^> API Keys
echo     Update MQ_API_KEY/MQ_API_SECRET in PHP + Python .env, then restart.
if "!IS_ONPREM!"=="true" echo  2. MinIO bucket -- open http://localhost:9011 ^> Create bucket: !S3_BUCKET!
echo  3. PHP database installer -- open https://!DOMAIN!/UAC/install
echo  4. Copy firebase-service-account.json into sce-php-app container
echo  5. Copy APNs .p8 key into sce-php-app container
echo  6. Set SCE_PASSWORD in eAssist-AI-Service\.env, then restart
if "!CCTV_ENABLED!"=="true" echo  7. Add VSS_PRIVATE_KEY and VSS_PUBLIC_KEY to SCE-Python-Service\.env
echo ================================================================
echo.
pause
exit /b 0

:: ─────────────────────────────────────────────────────────────────────────────
:resolve_repo
    :: %~1 = variable name, %~2 = label, %~3 = current value
    if not "%~3"=="" (
        echo   [OK] Found %~2 -^> %~3
    ) else (
        echo   [WARN] Could not find %~2
        set /p "_rr_input=  Enter folder name inside %ROOT% (or leave blank to skip): "
        if not "!_rr_input!"=="" (
            set "_rr_full=%ROOT%\!_rr_input!"
            :: Allow absolute path too
            echo !_rr_input! | findstr /r "^[A-Za-z]:\\" >nul 2>&1 && set "_rr_full=!_rr_input!"
            if exist "!_rr_full!\" (
                set "%~1=!_rr_full!"
                echo   [OK] Using !_rr_full!
            ) else (
                echo   [WARN] Path not found: !_rr_full! -- skipping %~2
            )
        ) else (
            echo   [SKIP] Skipping %~2
        )
        set "_rr_input="
    )
    exit /b 0

:rand16
    set "%~1=%RANDOM%%RANDOM%%RANDOM%"
    exit /b 0

:rand32
    set "%~1=%RANDOM%%RANDOM%%RANDOM%%RANDOM%%RANDOM%"
    exit /b 0

:to_lower
    for %%C in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        set "%~1=!%~1:%%C=%%C!"
    )
    exit /b 0
