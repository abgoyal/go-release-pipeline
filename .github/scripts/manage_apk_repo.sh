#!/bin/bash
set -euo pipefail
set -x

echo "--- Managing Alpine (APK) Repository ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/apk"
ARTIFACTS_DIR="artifacts"
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1
ABUILD_KEY_NAME="ci-key"

# --- CHECK REQUIRED TOOLS ---
command -v openssl >/dev/null || { echo "[ERROR] openssl not found"; exit 1; }
command -v abuild-sign >/dev/null || { echo "[ERROR] abuild-sign not found"; exit 1; }
command -v apk >/dev/null || { echo "[ERROR] apk not found"; exit 1; }

# --- SETUP ABUILD KEYS ---
mkdir -p "$HOME/.abuild"
if [ ! -f "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" ]; then
    echo "${APK_PRIVATE_KEY}" > "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
    chmod 600 "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
    openssl rsa -in "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" -pubout > "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa.pub"
else
    echo "[SKIP] Private key already exists at $HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
fi

# Make public key available for apk verification inside the container
mkdir -p /etc/apk/keys
cp "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa.pub" /etc/apk/keys/

# --- PROCESS EACH ARCHITECTURE ---
for arch in amd64 arm64; do
    echo "--- Processing architecture: $arch ---"
    ARCH_DIR="$REPO_DIR/$arch"
    mkdir -p "$ARCH_DIR"

    # --- CLEANUP OLD PACKAGES ---
    echo "[CLEANUP] Cleaning up old packages in $ARCH_DIR..."
    versions=$(find "$ARCH_DIR" -name '*.apk' -exec basename {} \; | \
               grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -rV | uniq || true)

    if [ -n "$versions" ]; then
        current_major=$(echo "$NEW_VERSION" | cut -d. -f1)
        previous_major_num=$((${current_major#v} - 1))
        previous_major="v${previous_major_num}"

        to_keep_current=$(echo "$versions" | grep "^$current_major" | head -n $KEEP_CURRENT_MAJOR)
        to_keep_previous=$(echo "$versions" | grep "^$previous_major" | head -n $KEEP_PREVIOUS_MAJOR)
        to_keep=$(echo -e "${to_keep_current}\n${to_keep_previous}" | sed '/^\s*$/d' | sort | uniq)
        to_delete=$(comm -23 <(echo "$versions" | sort) <(echo "$to_keep" | sort))

        for v in $to_delete; do
            echo "[CLEANUP] Removing files for version $v"
            find "$ARCH_DIR" -name "*${v}*${arch}.apk" -exec rm -v {} +
        done
    fi

    # --- ADD NEW PACKAGES ---
    APK_FILES=$(find "$ARTIFACTS_DIR" -name "*${arch}*.apk" || true)
    if [ -n "$APK_FILES" ]; then
        echo "[ADD] Adding new packages for $arch..."
        cp $APK_FILES "$ARCH_DIR/"
    fi

    # --- SIGN & REGENERATE METADATA ---
    if [ -n "$(ls -A "$ARCH_DIR"/*.apk 2>/dev/null)" ]; then
        echo "[PUBLISH] Signing packages and regenerating repository metadata for $arch..."
        abuild-sign -k "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" "$ARCH_DIR"/*.apk
        apk index -o "$ARCH_DIR/APKINDEX.tar.gz" "$ARCH_DIR"/*.apk
        abuild-sign -k "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" "$ARCH_DIR/APKINDEX.tar.gz"
    fi
done

# --- PUBLISH PUBKEY AT REPO ROOT ---
cp "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa.pub" "$REPO_DIR/pubkey"

echo "[OK] Alpine repository updated."
echo "[INFO] Public key is in: $REPO_DIR/pubkey"
