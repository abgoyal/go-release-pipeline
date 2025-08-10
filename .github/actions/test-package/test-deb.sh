#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"

# --- FIX: Match the GoReleaser filename structure exactly ---
# Old: DEB_FILE="${REPO_NAME}_${TAG#v}_${ARCH}.deb"
# New: Includes "_linux_" and correctly uses the TAG variable.
DEB_FILE="${REPO_NAME}_${TAG#v}_linux_${ARCH}.deb"

DEB_URL="${REPO_URL}/deb/pool/main/g/${REPO_NAME}/${DEB_FILE}"

docker run --rm --platform "$PLATFORM" ubuntu:latest sh -c " \
    set -ex && \
    echo '--- 1. Installing test dependencies ---' && \
    apt-get update && apt-get install -y wget ca-certificates curl gpg && \
    echo '--- 2. Testing first-time install with dpkg ---' && \
    wget \"${DEB_URL}\" && \
    dpkg -i \"${DEB_FILE}\" && \
    echo '--- 3. Verifying repository setup ---' && \
    apt-get update && \
    apt-get upgrade -y --dry-run && \
    echo '--- 4. Testing uninstall and re-install from apt repository ---' && \
    apt-get remove -y ${REPO_NAME} && \
    ! command -v ${REPO_NAME} && \
    apt-get install -y ${REPO_NAME} && \
    echo '--- 5. Verifying the final application is executable ---' && \
    \"${REPO_NAME}\" --version | grep \"${TAG#v}\""

