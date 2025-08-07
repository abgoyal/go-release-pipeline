#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"
RPM_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64")

docker run --rm --platform "$PLATFORM" fedora:latest sh -c " \
    set -ex && \
    dnf install -y dnf-plugins-core && \
    tee /etc/yum.repos.d/${REPO_NAME}.repo <<EOF
[${REPO_NAME}]
name=${REPO_NAME}
baseurl=${REPO_URL}/rpm/${RPM_ARCH}
enabled=1
gpgcheck=1
gpgkey=${REPO_URL}/rpm/public.key
EOF
    dnf install -y ${REPO_NAME} && \
    ${REPO_NAME} --version | grep ${TAG#v}"

