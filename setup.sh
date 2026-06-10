#!/usr/bin/env bash
# SCE — Ecosystem Setup
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.sh | bash
#   wget -qO- https://raw.githubusercontent.com/dev-itbs/SCE-Installation/main/setup.sh | bash

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[36m'; GREEN='\033[32m'
YELLOW='\033[33m'; RED='\033[31m'; GREY='\033[90m'; RESET='\033[0m'

log()   { echo -e "${CYAN}${1}${RESET}"; }
ok()    { echo -e "${GREEN}  ✔ ${1}${RESET}"; }
warn()  { echo -e "${YELLOW}  ⚠ ${1}${RESET}"; }
err()   { echo -e "${RED}  ✖ ${1}${RESET}"; }
dim()   { echo -e "${GREY}    ${1}${RESET}"; }
title() { echo -e "\n${BOLD}${CYAN}${1}${RESET}"; }
hr()    { echo -e "${GREY}$(printf '─%.0s' {1..60})${RESET}"; }

# ── Repository definitions ────────────────────────────────────────────────────
declare -A REPO_URLS=(
    [VaultFlow360]="https://github.com/dev-itbs/VaultFlow360.git"
    [SCE-Installation]="https://github.com/dev-itbs/SCE-Installation.git"
    [SCE-PHP-SYSTEMS]="https://github.com/dev-itbs/SCE-PHP-SYSTEMS.git"
    [SCE-Python-Service]="https://github.com/dev-itbs/SCE-Python-Service.git"
    [SCE-Vue-CPA]="https://github.com/dev-itbs/SCE-Vue-CPA.git"
    [eAssist-AI-Service]="https://github.com/dev-itbs/eAssist-AI-Service.git"
)

declare -A REPO_LABELS=(
    [VaultFlow360]="VaultFlow360        (PostgreSQL HA cluster)"
    [SCE-Installation]="SCE-Installation    (Installer + infra prerequisites)"
    [SCE-PHP-SYSTEMS]="SCE-PHP-SYSTEMS     (UAC / CRMS / EMS — PHP app)"
    [SCE-Python-Service]="SCE-Python-Service  (FastAPI + BullMQ workers)"
    [SCE-Vue-CPA]="SCE-Vue-CPA         (Citizen Portal App — Quasar PWA/Android/iOS)"
    [eAssist-AI-Service]="eAssist-AI-Service  (AI assistant — Bun + CopilotKit)"
)

REPO_ORDER=(
    VaultFlow360
    SCE-Installation
    SCE-PHP-SYSTEMS
    SCE-Python-Service
    SCE-Vue-CPA
    eAssist-AI-Service
)

# ── Pre-flight ────────────────────────────────────────────────────────────────
title "SCE — Ecosystem Setup"
hr
echo "This script clones all SCE repositories into a single parent folder."
echo "If a repository already exists it will be updated (git pull)."
echo ""

if ! command -v git &>/dev/null; then
    err "git is not installed. Please install git first."
    exit 1
fi

# ── Parent folder ─────────────────────────────────────────────────────────────
DEFAULT_FOLDER="SCE-ECOSYSTEM"
printf "${BOLD}Parent folder name${RESET} [${CYAN}${DEFAULT_FOLDER}${RESET}]: "
read -r PARENT_INPUT
PARENT_FOLDER="${PARENT_INPUT:-$DEFAULT_FOLDER}"
PARENT_FOLDER="$(pwd)/${PARENT_FOLDER}"

echo ""
echo -e "Repositories will be cloned into: ${BOLD}${PARENT_FOLDER}${RESET}"
echo ""

# ── Optional GitHub token ─────────────────────────────────────────────────────
printf "${BOLD}GitHub Personal Access Token${RESET} (leave blank if repos are public): "
read -rs GH_TOKEN
echo ""
echo ""

inject_token() {
    local url="$1"
    [[ -n "$GH_TOKEN" ]] && echo "${url/https:\/\//https://${GH_TOKEN}@}" || echo "$url"
}

# ── Select repos ──────────────────────────────────────────────────────────────
title "Select repositories"
hr
echo "Press Enter to accept Yes. Type N to skip."
echo "Type C to use a custom URL instead of the default."
echo ""

declare -A SELECTED
declare -A FINAL_URLS

for key in "${REPO_ORDER[@]}"; do
    printf "  Clone ${BOLD}${REPO_LABELS[$key]}${RESET}? [Y/n/c]: "
    read -r ans
    ans="${ans,,}"
    if [[ "$ans" == "n" ]]; then
        SELECTED[$key]=0
    elif [[ "$ans" == "c" ]]; then
        SELECTED[$key]=1
        printf "  Custom URL for ${key} [${REPO_URLS[$key]}]: "
        read -r custom_url
        FINAL_URLS[$key]="${custom_url:-${REPO_URLS[$key]}}"
    else
        SELECTED[$key]=1
        FINAL_URLS[$key]="${REPO_URLS[$key]}"
    fi
done

# ── Check at least one selected ───────────────────────────────────────────────
any_selected=0
for key in "${REPO_ORDER[@]}"; do
    [[ "${SELECTED[$key]}" == "1" ]] && any_selected=1 && break
done

if [[ $any_selected -eq 0 ]]; then
    warn "No repositories selected. Exiting."
    exit 0
fi

# ── Create parent folder ──────────────────────────────────────────────────────
mkdir -p "$PARENT_FOLDER"
ok "Using folder: $PARENT_FOLDER"

# ── Clone / pull ──────────────────────────────────────────────────────────────
title "Cloning repositories"
hr

FAILED=0

clone_or_pull() {
    local key="$1"
    local url
    url="$(inject_token "${FINAL_URLS[$key]}")"
    local display_url="${FINAL_URLS[$key]}"
    local target="${PARENT_FOLDER}/${key}"

    echo ""
    echo -e "${BOLD}→ ${key}${RESET}"
    dim "${display_url}"
    dim "→ ${target}"

    if [[ -d "${target}/.git" ]]; then
        warn "Already cloned — running git pull..."
        if git -C "$target" pull --ff-only; then
            ok "Updated"
        else
            err "git pull failed for ${key}"
            printf "  Enter correct URL to re-clone, or leave blank to skip: "
            read -r retry_url
            if [[ -n "$retry_url" ]]; then
                local retry_auth
                retry_auth="$(inject_token "$retry_url")"
                rm -rf "$target"
                if git clone "$retry_auth" "$target"; then
                    ok "Cloned from new URL"
                else
                    err "Clone failed again for ${key}"
                    FAILED=1
                fi
            else
                FAILED=1
            fi
        fi
    else
        if git clone "$url" "$target"; then
            ok "Cloned"
        else
            err "git clone failed for ${key}"
            printf "  Enter correct URL to try again, or leave blank to skip: "
            read -r retry_url
            if [[ -n "$retry_url" ]]; then
                local retry_auth
                retry_auth="$(inject_token "$retry_url")"
                if git clone "$retry_auth" "$target"; then
                    ok "Cloned from new URL"
                else
                    err "Clone failed again for ${key}"
                    FAILED=1
                fi
            else
                FAILED=1
            fi
        fi
    fi
}

for key in "${REPO_ORDER[@]}"; do
    [[ "${SELECTED[$key]}" == "1" ]] && clone_or_pull "$key"
done

# ── Summary ───────────────────────────────────────────────────────────────────
title "Summary"
hr
echo ""

if [[ $FAILED -eq 0 ]]; then
    ok "All done!"
    log "Your ecosystem is in: ${PARENT_FOLDER}"
    echo ""
    echo -e "${GREY}Next steps:${RESET}"
    echo "  1. cd ${PARENT_FOLDER}"
    echo "  2. Read SCE-Installation/README.md for full setup instructions"
    echo "  3. Run: node SCE-Installation/docker-setup/configure.js"
    echo ""
else
    warn "Some repositories failed. Check the errors above and re-run."
    exit 1
fi
