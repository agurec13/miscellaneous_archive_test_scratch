#!/usr/bin/env bash
set -euo pipefail

# Generic first-stage bootstrap for Debian.
# Publish this file separately, then run it with one line on a new server:
#   sudo REPO_URL='https://github.com/owner/private-repo.git' REPO_BRANCH='develop' bash <(curl -fsSL PUBLIC_URL)
#
# Optional variables:
#   REPO_URL        - required HTTPS URL of the private GitHub repository
#   REPO_BRANCH     - branch to install, default: main
#   INSTALL_SCRIPT  - relative path inside the repo, default: deploy/bootstrap-debian.sh
#   ENABLE_NGINX    - true/false, default: true

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-deploy/bootstrap-debian.sh}"
ENABLE_NGINX="${ENABLE_NGINX:-true}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root, for example:"
    echo "  sudo REPO_URL='https://github.com/owner/private-repo.git' bash <(curl -fsSL PUBLIC_URL)"
    exit 1
fi

if [[ -z "${REPO_URL}" ]]; then
    echo "Set REPO_URL to the HTTPS address of the private GitHub repository."
    exit 1
fi

if [[ "${REPO_URL}" == git@* ]]; then
    echo "Use an HTTPS GitHub repository URL with this bootstrap."
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git gh

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    gh auth login --hostname github.com --git-protocol https
fi

gh auth setup-git --hostname github.com

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
CHECKOUT_DIR="${WORK_DIR}/repo"

git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${CHECKOUT_DIR}"

if [[ ! -f "${CHECKOUT_DIR}/${INSTALL_SCRIPT}" ]]; then
    echo "Install script not found in repository: ${INSTALL_SCRIPT}"
    exit 1
fi

SOURCE_REPO_DIR="${CHECKOUT_DIR}" \
ENABLE_NGINX="${ENABLE_NGINX}" \
bash "${CHECKOUT_DIR}/${INSTALL_SCRIPT}"
