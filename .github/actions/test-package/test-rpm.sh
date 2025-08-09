#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"

docker run --rm --platform "$PLATFORM" fedora:latest sh -c " \
    set -ex && \
    dnf install -y dnf-plugins-core && \
    tee /etc/yum.repos.d/${REPO_NAME}.repo <<EOF
[${REPO_NAME}]
name=${REPO_NAME}
# --- FIX: Use the \$basearch variable for dnf ---
# The backslash ensures that \$basearch is written literally to the file.
baseurl=${REPO_URL}/rpm/\\\$basearch
enabled=1
gpgcheck=1
gpgkey=${REPO_URL}/rpm/public.key
EOF
    dnf install -y ${REPO_NAME} && \
    ${REPO_NAME} --version | grep ${TAG#v}"

