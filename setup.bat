@echo off
setlocal EnableDelayedExpansion
title SCE — Ecosystem Setup

echo.
echo ============================================================
echo  SCE -- Ecosystem Setup
echo ============================================================
echo  This script clones all SCE repositories into one folder.
echo  If a repo already exists it will be updated (git pull).
echo ============================================================
echo.

:: ── Check git ────────────────────────────────────────────────────────────────
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git is not installed or not in PATH.
    echo         Download from https://git-scm.com/download/win
    pause
    exit /b 1
)

:: ── Ask for parent folder ─────────────────────────────────────────────────────
set "DEFAULT_FOLDER=SCE-ECOSYSTEM"
set /p "PARENT_FOLDER=Parent folder name [%DEFAULT_FOLDER%]: "
if "%PARENT_FOLDER%"=="" set "PARENT_FOLDER=%DEFAULT_FOLDER%"

echo.
echo Repositories will be cloned into: %CD%\%PARENT_FOLDER%
echo.

:: ── Ask for GitHub token (optional) ──────────────────────────────────────────
set /p "GH_TOKEN=GitHub Personal Access Token (leave blank if repos are public): "
echo.

:: ── Repository URLs ───────────────────────────────────────────────────────────
set "URL_VAULT=https://github.com/dev-itbs/VaultFlow360.git"
set "URL_INSTALL=https://github.com/dev-itbs/SCE-Installation.git"
set "URL_PHP=https://github.com/dev-itbs/SCE-PHP-SYSTEMS.git"
set "URL_PYTHON=https://github.com/dev-itbs/SCE-Python-Service.git"
set "URL_CPA=https://github.com/dev-itbs/SCE-Vue-CPA.git"
set "URL_EASSIST=https://github.com/dev-itbs/eAssist-AI-Service.git"

:: Inject token into URL if provided
if not "%GH_TOKEN%"=="" (
    set "URL_VAULT=https://%GH_TOKEN%@github.com/dev-itbs/VaultFlow360.git"
    set "URL_INSTALL=https://%GH_TOKEN%@github.com/dev-itbs/SCE-Installation.git"
    set "URL_PHP=https://%GH_TOKEN%@github.com/dev-itbs/SCE-PHP-SYSTEMS.git"
    set "URL_PYTHON=https://%GH_TOKEN%@github.com/dev-itbs/SCE-Python-Service.git"
    set "URL_CPA=https://%GH_TOKEN%@github.com/dev-itbs/SCE-Vue-CPA.git"
    set "URL_EASSIST=https://%GH_TOKEN%@github.com/dev-itbs/eAssist-AI-Service.git"
)

:: ── Select repos ──────────────────────────────────────────────────────────────
echo ============================================================
echo  Select repositories (press Enter for Yes, type N to skip)
echo ============================================================
echo.

call :ask_repo "VaultFlow360        (PostgreSQL HA cluster)"              CLONE_VAULT
call :ask_repo "SCE-Installation    (Installer + infra prerequisites)"    CLONE_INSTALL
call :ask_repo "SCE-PHP-SYSTEMS     (UAC / CRMS / EMS - PHP app)"         CLONE_PHP
call :ask_repo "SCE-Python-Service  (FastAPI + BullMQ workers)"           CLONE_PYTHON
call :ask_repo "SCE-Vue-CPA         (Citizen Portal App - Quasar/PWA)"    CLONE_CPA
call :ask_repo "eAssist-AI-Service  (AI assistant - Bun + CopilotKit)"    CLONE_EASSIST

echo.

:: ── Create parent folder ──────────────────────────────────────────────────────
if not exist "%PARENT_FOLDER%" (
    mkdir "%PARENT_FOLDER%"
    echo [OK] Created folder: %PARENT_FOLDER%
)

:: ── Clone / pull ──────────────────────────────────────────────────────────────
echo.
echo ============================================================
echo  Cloning repositories
echo ============================================================
echo.

set "FAILED="

if "%CLONE_VAULT%"=="1"   call :clone_or_pull "%URL_VAULT%"   "%PARENT_FOLDER%\VaultFlow360"
if "%CLONE_INSTALL%"=="1" call :clone_or_pull "%URL_INSTALL%" "%PARENT_FOLDER%\SCE-Installation"
if "%CLONE_PHP%"=="1"     call :clone_or_pull "%URL_PHP%"     "%PARENT_FOLDER%\SCE-PHP-SYSTEMS"
if "%CLONE_PYTHON%"=="1"  call :clone_or_pull "%URL_PYTHON%"  "%PARENT_FOLDER%\SCE-Python-Service"
if "%CLONE_CPA%"=="1"     call :clone_or_pull "%URL_CPA%"     "%PARENT_FOLDER%\SCE-Vue-CPA"
if "%CLONE_EASSIST%"=="1" call :clone_or_pull "%URL_EASSIST%" "%PARENT_FOLDER%\eAssist-AI-Service"

:: ── Summary ───────────────────────────────────────────────────────────────────
echo.
echo ============================================================

if defined FAILED (
    echo  [WARNING] Some repositories failed. Check errors above.
) else (
    echo  All done!
    echo  Your ecosystem is in: %CD%\%PARENT_FOLDER%
    echo.
    echo  Next steps:
    echo    1. cd %PARENT_FOLDER%
    echo    2. Read SCE-Installation\README.md for setup instructions
    echo    3. Start VaultFlow360, then prerequisite, then the apps.
)

echo ============================================================
echo.
pause
exit /b 0

:: ─────────────────────────────────────────────────────────────────────────────
:ask_repo
    set /p "_ans=  Clone %~1? [Y/n]: "
    if /i "%_ans%"=="n" (
        set "%~2=0"
    ) else (
        set "%~2=1"
    )
    set "_ans="
    exit /b 0

:clone_or_pull
    set "_url=%~1"
    set "_dir=%~2"
    echo.
    echo -- %_dir%
    if exist "%_dir%\.git" (
        echo    Already cloned -- running git pull...
        git -C "%_dir%" pull --ff-only
        if errorlevel 1 (
            echo    [ERROR] git pull failed for %_dir%
            set "FAILED=1"
        ) else (
            echo    [OK] Updated
        )
    ) else (
        git clone "%_url%" "%_dir%"
        if errorlevel 1 (
            echo    [ERROR] git clone failed for %_dir%
            set "FAILED=1"
        ) else (
            echo    [OK] Cloned
        )
    )
    exit /b 0
