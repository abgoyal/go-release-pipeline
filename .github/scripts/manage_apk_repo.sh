#!/bin/bash
set -eou pipefail

set -x
echo "--- Managing Alpine (APK) Repository ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/apk"
ARTIFACTS_DIR="artifacts"
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1

# --- GPG SETUP ---
GPG_HOME=$(mktemp -d)
trap 'rm -rf -- "$GPG_HOME"' EXIT
chmod 700 "$GPG_HOME"
export GNUPGHOME="$GPG_HOME"

echo "${GPG_PRIVATE_KEY}" | gpg --batch --import
GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format long | grep 'sec ' | awk '{print $2}' | cut -d'/' -f2)
ABUILD_KEY_NAME="ci-key"
mkdir -p ~/.abuild
echo $HOME/.abuild/${ABUILD_KEY_NAME}.rsa
gpg --export-secret-keys --armor "$GPG_KEY_ID" > $HOME/.abuild/${ABUILD_KEY_NAME}.rsa
find $HOME/.abuild

# --- PROCESS EACH ARCHITECTURE ---
#for arch in x86_64 aarch64; do
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
        # We need to re-sign existing packages as well if they were not touched
        for pkg in "$ARCH_DIR"/*.apk; do abuild-sign -k "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" "$pkg"; done
        apk index -o "$ARCH_DIR/APKINDEX.tar.gz" "$ARCH_DIR"/*.apk
        abuild-sign -k "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" "$ARCH_DIR/APKINDEX.tar.gz"
        gpg --export --armor "$GPG_KEY_ID" > "$ARCH_DIR/${ABUILD_KEY_NAME}.rsa.pub"
    fi
done

echo "[OK] Alpine repository updated successfully."

# --- CLEAN GPG ---
rm -rf ~/.gnupg/
