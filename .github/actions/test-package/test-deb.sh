#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"

# Construct the direct URL to the .deb file in your repository's pool
DEB_FILE="${REPO_NAME}_${TAG#v}_${ARCH}.deb"
DEB_URL="${REPO_URL}/deb/pool/main/g/${REPO_NAME}/${DEB_FILE}"

docker run --rm --platform "$PLATFORM" ubuntu:latest sh -c " \
    set -ex && \
    \
    # --- 1. SETUP: Install dependencies for the test itself ---
    echo '--- 1. Installing test dependencies ---' && \
    apt-get update && apt-get install -y wget ca-certificates && \
    \
    # --- 2. TEST: First-time install via direct download ---
    # This simulates a user installing the .deb manually and runs the postinst script.
    echo '--- 2. Testing first-time install with dpkg ---' && \
    wget \"${DEB_URL}\" && \
    dpkg -i \"${DEB_FILE}\" && \
    \
    # --- 3. TEST: Verify the postinst script configured the repository ---
    # If the postinst script ran correctly, apt-get update will now succeed.
    echo '--- 3. Verifying repository setup ---' && \
    apt-get update && \
    apt-get upgrade -y --dry-run && \
    \
    # --- 4. TEST: Clean uninstall and reinstall from the APT repository ---
    # This proves the full package lifecycle works as expected.
    echo '--- 4. Testing uninstall and re-install from apt repository ---' && \
    apt-get remove -y ${REPO_NAME} && \
    ! command -v ${REPO_NAME} && \
    apt-get install -y ${REPO_NAME} && \
    \
    # --- 5. FINAL VERIFICATION: Check the application version ---
    echo '--- 5. Verifying the final application is executable ---' && \
    \"${REPO_NAME}\" --version | grep \"${TAG#v}\""

