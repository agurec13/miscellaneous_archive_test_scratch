#!/usr/bin/env bash
set -euo pipefail

# First-stage bootstrap for Debian.
# Installs prerequisites, authenticates to GitHub, clones the private repo
# into a temporary directory, then launches the second-stage installer from it.
#
# Example:
# sudo REPO_URL='https://github.com/OWNER/REPO.git' REPO_BRANCH='develop' \
#   bash <(curl -fsSL 'https://raw.githubusercontent.com/OWNER/PUBLIC_REPO/main/bootstrap.sh')

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-deploy/bootstrap-debian.sh}"
ENABLE_NGINX="${ENABLE_NGINX:-true}"

if [[ -z "${REPO_URL}" ]]; then
    echo "REPO_URL is required."
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git gh

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

REPO_SLUG="$(normalize_repo_slug "${REPO_URL}")"

if ! gh auth status -h github.com >/dev/null 2>&1; then
    echo "GitHub authentication is required to download the private repository."
    gh auth login -h github.com -p https -w
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

REPO_DIR="${TMP_DIR}/repo"

gh repo clone "${REPO_SLUG}" "${REPO_DIR}" -- --branch "${REPO_BRANCH}"

INSTALL_PATH="${REPO_DIR}/${INSTALL_SCRIPT}"
if [[ ! -f "${INSTALL_PATH}" ]]; then
    echo "Install script not found: ${INSTALL_SCRIPT}"
    exit 1
fi

# Important:
# remove REPO_URL from the environment before launching stage 2,
# otherwise the second script will try to git clone again into /opt/...
env -u REPO_URL \
    SOURCE_REPO_DIR="${REPO_DIR}" \
    REPO_BRANCH="${REPO_BRANCH}" \
    ENABLE_NGINX="${ENABLE_NGINX}" \
    bash "${INSTALL_PATH}"

