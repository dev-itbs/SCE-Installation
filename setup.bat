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
if "!PARENT_FOLDER!"=="" set "PARENT_FOLDER=%DEFAULT_FOLDER%"

echo.
echo Repositories will be cloned into: %CD%\!PARENT_FOLDER!
echo.

:: ── Ask for GitHub token (optional) ──────────────────────────────────────────
set /p "GH_TOKEN=GitHub Personal Access Token (leave blank if repos are public): "
echo.

:: ── Default repository URLs ───────────────────────────────────────────────────
set "DEF_URL_VAULT=https://github.com/dev-itbs/VaultFlow360.git"
set "DEF_URL_INSTALL=https://github.com/dev-itbs/SCE-Installation.git"
set "DEF_URL_PHP=https://github.com/dev-itbs/SCE-PHP-SYSTEMS.git"
set "DEF_URL_PYTHON=https://github.com/dev-itbs/SCE-Python-Service.git"
set "DEF_URL_CPA=https://github.com/dev-itbs/SCE-Vue-CPA.git"
set "DEF_URL_EASSIST=https://github.com/dev-itbs/eAssist-AI-Service.git"

:: Final URLs start as defaults (token injected later per-repo)
set "URL_VAULT=!DEF_URL_VAULT!"
set "URL_INSTALL=!DEF_URL_INSTALL!"
set "URL_PHP=!DEF_URL_PHP!"
set "URL_PYTHON=!DEF_URL_PYTHON!"
set "URL_CPA=!DEF_URL_CPA!"
set "URL_EASSIST=!DEF_URL_EASSIST!"

:: ── Select repos ──────────────────────────────────────────────────────────────
echo ============================================================
echo  Select repositories
echo  Press Enter = Yes,  N = skip,  C = enter custom URL
echo ============================================================
echo.

call :ask_repo "VaultFlow360        (PostgreSQL HA cluster)"              CLONE_VAULT   URL_VAULT
call :ask_repo "SCE-Installation    (Installer + infra prerequisites)"    CLONE_INSTALL URL_INSTALL
call :ask_repo "SCE-PHP-SYSTEMS     (UAC / CRMS / EMS - PHP app)"         CLONE_PHP     URL_PHP
call :ask_repo "SCE-Python-Service  (FastAPI + BullMQ workers)"           CLONE_PYTHON  URL_PYTHON
call :ask_repo "SCE-Vue-CPA         (Citizen Portal App - Quasar/PWA)"    CLONE_CPA     URL_CPA
call :ask_repo "eAssist-AI-Service  (AI assistant - Bun + CopilotKit)"    CLONE_EASSIST URL_EASSIST

echo.

:: ── Create parent folder ──────────────────────────────────────────────────────
if not exist "!PARENT_FOLDER!" (
    mkdir "!PARENT_FOLDER!"
    echo [OK] Created folder: !PARENT_FOLDER!
)

:: ── Clone / pull ──────────────────────────────────────────────────────────────
echo.
echo ============================================================
echo  Cloning repositories
echo ============================================================
echo.

set "FAILED="

if "!CLONE_VAULT!"=="1"   call :clone_or_pull "!URL_VAULT!"   "!PARENT_FOLDER!\VaultFlow360"
if "!CLONE_INSTALL!"=="1" call :clone_or_pull "!URL_INSTALL!" "!PARENT_FOLDER!\SCE-Installation"
if "!CLONE_PHP!"=="1"     call :clone_or_pull "!URL_PHP!"     "!PARENT_FOLDER!\SCE-PHP-SYSTEMS"
if "!CLONE_PYTHON!"=="1"  call :clone_or_pull "!URL_PYTHON!"  "!PARENT_FOLDER!\SCE-Python-Service"
if "!CLONE_CPA!"=="1"     call :clone_or_pull "!URL_CPA!"     "!PARENT_FOLDER!\SCE-Vue-CPA"
if "!CLONE_EASSIST!"=="1" call :clone_or_pull "!URL_EASSIST!" "!PARENT_FOLDER!\eAssist-AI-Service"

:: ── Summary ───────────────────────────────────────────────────────────────────
echo.
echo ============================================================

if defined FAILED (
    echo  [WARNING] Some repositories failed. Check errors above.
) else (
    echo  All done!
    echo  Your ecosystem is in: %CD%\!PARENT_FOLDER!
    echo.
    echo  Next steps:
    echo    1. cd !PARENT_FOLDER!
    echo    2. Read SCE-Installation\README.md for setup instructions
    echo    3. Run: node SCE-Installation\docker-setup\configure.js
)

echo ============================================================
echo.
pause
exit /b 0

:: ─────────────────────────────────────────────────────────────────────────────
:ask_repo
    :: %~1=label  %~2=clone_flag_var  %~3=url_var
    set /p "_ans=  Clone %~1? [Y/n/c]: "
    if /i "!_ans!"=="n" (
        set "%~2=0"
    ) else if /i "!_ans!"=="c" (
        set "%~2=1"
        set /p "_custom=  Custom URL for %~1 [!%~3!]: "
        if not "!_custom!"=="" set "%~3=!_custom!"
    ) else (
        set "%~2=1"
    )
    set "_ans=" & set "_custom="
    exit /b 0

:: ─────────────────────────────────────────────────────────────────────────────
:clone_or_pull
    set "_url=%~1"
    set "_dir=%~2"

    :: Inject token if provided
    if not "!GH_TOKEN!"=="" (
        set "_url=!_url:https://=https://!GH_TOKEN!@!"
    )

    echo.
    echo -- %~2
    if exist "%~2\.git" (
        echo    Already cloned -- running git pull...
        git -C "%~2" pull --ff-only
        if errorlevel 1 (
            echo    [ERROR] git pull failed.
            set /p "_retry=  Enter correct URL to re-clone, or leave blank to skip: "
            if not "!_retry!"=="" (
                if not "!GH_TOKEN!"=="" set "_retry=!_retry:https://=https://!GH_TOKEN!@!"
                rmdir /s /q "%~2" 2>nul
                git clone "!_retry!" "%~2"
                if errorlevel 1 (
                    echo    [ERROR] Clone failed again.
                    set "FAILED=1"
                ) else (
                    echo    [OK] Cloned from new URL
                )
            ) else (
                set "FAILED=1"
            )
            set "_retry="
        ) else (
            echo    [OK] Updated
        )
    ) else (
        git clone "!_url!" "%~2"
        if errorlevel 1 (
            echo    [ERROR] git clone failed.
            set /p "_retry=  Enter correct URL to try again, or leave blank to skip: "
            if not "!_retry!"=="" (
                if not "!GH_TOKEN!"=="" set "_retry=!_retry:https://=https://!GH_TOKEN!@!"
                git clone "!_retry!" "%~2"
                if errorlevel 1 (
                    echo    [ERROR] Clone failed again.
                    set "FAILED=1"
                ) else (
                    echo    [OK] Cloned from new URL
                )
            ) else (
                set "FAILED=1"
            )
            set "_retry="
        ) else (
            echo    [OK] Cloned
        )
    )
    exit /b 0
