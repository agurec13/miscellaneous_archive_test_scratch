#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-deploy/bootstrap-debian.sh}"
ENABLE_NGINX="${ENABLE_NGINX:-true}"

if [[ -z "${REPO_URL}" ]]; then
    echo "REPO_URL is required." >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo or as root." >&2
    exit 1
fi

if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    echo "Interactive terminal is required." >&2
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git gh

tty_print() {
    printf '%b' "$1" > /dev/tty
}

tty_clear_lines() {
    local lines="$1"
    local i=0

    for ((i = 0; i < lines; i++)); do
        printf '\033[1A\033[2K\r' > /dev/tty
    done
}

show_cursor() {
    printf '\033[?25h' > /dev/tty
}

hide_cursor() {
    printf '\033[?25l' > /dev/tty
}

prompt_secret() {
    local __result_var="$1"
    local label="$2"
    local value=""

    while true; do
        tty_print "${label}: "
        IFS= read -r -s value < /dev/tty
        tty_print "\n"

        if [[ -n "${value}" ]]; then
            printf -v "${__result_var}" '%s' "${value}"
            return
        fi

        tty_print "Value is required.\n"
    done
}

choose_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local key=""
    local esc=""

    tty_print "${prompt}\n"
    hide_cursor

    while true; do
        local i
        for i in "${!options[@]}"; do
            if (( i == selected )); then
                tty_print "  > ${options[$i]}\n"
            else
                tty_print "    ${options[$i]}\n"
            fi
        done

        IFS= read -r -s -n1 key < /dev/tty || true

        if [[ "${key}" == $'\x1b' ]]; then
            IFS= read -r -s -n2 esc < /dev/tty || true
            case "${esc}" in
                '[A'|'OA')
                    ((selected = (selected - 1 + ${#options[@]}) % ${#options[@]}))
                    ;;
                '[B'|'OB')
                    ((selected = (selected + 1) % ${#options[@]}))
                    ;;
            esac
            tty_clear_lines "${#options[@]}"
            continue
        fi

        if [[ -z "${key}" ]]; then
            break
        fi

        tty_clear_lines "${#options[@]}"
    done

    show_cursor
    printf '%s' "${selected}"
}

normalize_repo_slug() {
    local input="$1"
    local value="${input%.git}"

    value="${value#https://github.com/}"
    value="${value#http://github.com/}"
    value="${value#git@github.com:}"
    value="${value#ssh://git@github.com/}"
    value="${value#/}"
    value="${value%/}"

    if [[ "${value}" != */* ]]; then
        echo "Could not parse GitHub repository from REPO_URL: ${input}" >&2
        exit 1
    fi

    printf '%s' "${value}"
}

authenticate_github() {
    local token=""
    local choice=""

    unset GH_TOKEN GITHUB_TOKEN

    if gh auth status -h github.com >/dev/null 2>&1; then
        choice="$(choose_option \
            "GitHub auth detected. Use Up/Down arrows and Enter:" \
            "Use saved GitHub login" \
            "Login in browser (saved)" \
            "Use token for this run")"

        case "${choice}" in
            0)
                return
                ;;
            1)
                gh auth logout -h github.com >/dev/null 2>&1 || true
                gh auth login -h github.com -p https -w
                ;;
            2)
                gh auth logout -h github.com >/dev/null 2>&1 || true
                prompt_secret token "GitHub token"
                export GH_TOKEN="${token}"
                ;;
            *)
                echo "Unknown menu choice: ${choice}" >&2
                exit 1
                ;;
        esac
    else
        choice="$(choose_option \
            "Choose GitHub auth mode. Use Up/Down arrows and Enter:" \
            "Login in browser (saved)" \
            "Use token for this run")"

        case "${choice}" in
            0)
                gh auth login -h github.com -p https -w
                ;;
            1)
                prompt_secret token "GitHub token"
                export GH_TOKEN="${token}"
                ;;
            *)
                echo "Unknown menu choice: ${choice}" >&2
                exit 1
                ;;
        esac
    fi

    gh auth status -h github.com >/dev/null
}

cleanup() {
    show_cursor || true
    [[ -n "${TMP_DIR:-}" ]] && rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

REPO_SLUG="$(normalize_repo_slug "${REPO_URL}")"
authenticate_github

TMP_DIR="$(mktemp -d)"
REPO_DIR="${TMP_DIR}/repo"

gh repo clone "${REPO_SLUG}" "${REPO_DIR}" -- --branch "${REPO_BRANCH}"

INSTALL_PATH="${REPO_DIR}/${INSTALL_SCRIPT}"
if [[ ! -f "${INSTALL_PATH}" ]]; then
    echo "Install script not found: ${INSTALL_SCRIPT}" >&2
    exit 1
fi

env -u REPO_URL \
    SOURCE_REPO_DIR="${REPO_DIR}" \
    REPO_BRANCH="${REPO_BRANCH}" \
    ENABLE_NGINX="${ENABLE_NGINX}" \
    bash "${INSTALL_PATH}"
