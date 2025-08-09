#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"
APK_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64")

docker run --rm --platform "$PLATFORM" alpine:latest sh -c " \
    set -ex && \
    apk add --no-cache curl && \
    curl -fsSL \"${REPO_URL}/apk/ci-key.rsa.pub\" -o /etc/apk/keys/ci-key.rsa.pub && \
    \
    echo \"${REPO_URL}/apk\" >> /etc/apk/repositories && \
    \
    apk update && \
    apk add ${REPO_NAME} && \
    ${REPO_NAME} --version | grep ${TAG#v}"

