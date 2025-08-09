#!/bin/bash
set -ex

REPO_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
PLATFORM="linux/$ARCH"
COMPONENT="main"

docker run --rm --platform "$PLATFORM" ubuntu:latest sh -c " \
    set -ex && \
    apt-get update && apt-get install -y curl gpg && \
    curl -fsSL \"${REPO_URL}/deb/public.key\" | gpg --dearmor -o /usr/share/keyrings/${REPO_NAME}-archive-keyring.gpg && \
    echo \"deb [arch=${ARCH} signed-by=/usr/share/keyrings/${REPO_NAME}-archive-keyring.gpg] ${REPO_URL}/deb . ${COMPONENT}\" > /etc/apt/sources.list.d/${REPO_NAME}.list && \
    apt-get update && \
    apt-get install -y ${REPO_NAME} && \
    ${REPO_NAME} --version | grep ${TAG#v}"

