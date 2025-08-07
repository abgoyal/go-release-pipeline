#!/bin/bash
set -eou pipefail

set -x
echo "--- Managing RPM (YUM/DNF) Repository ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/rpm"
ARTIFACTS_DIR="artifacts"
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1

# --- GPG SETUP ---
echo "${GPG_PRIVATE_KEY}" | gpg --batch --import
GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format long | grep 'sec ' | awk '{print $2}' | cut -d'/' -f2)

# --- PROCESS EACH ARCHITECTURE ---
for arch in x86_64 aarch64; do
    echo "--- Processing architecture: $arch ---"
    ARCH_DIR="$REPO_DIR/$arch"
    mkdir -p "$ARCH_DIR"

    # --- CLEANUP OLD PACKAGES ---
    echo "[CLEANUP] Cleaning up old packages in $ARCH_DIR..."
    versions=$(find "$ARCH_DIR" -name "*.rpm" -exec basename {} \; | \
               grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -rV | uniq || true)

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
            find "$ARCH_DIR" -name "*${v}*${arch}.rpm" -exec rm -v {} +
        done
    fi

    # --- ADD NEW PACKAGES ---
    RPM_FILES=$(find "$ARTIFACTS_DIR" -name "*${arch}*.rpm" || true)
    if [ -n "$RPM_FILES" ]; then
        echo "[ADD] Adding new packages for $arch..."
        cp $RPM_FILES "$ARCH_DIR/"
    fi

    # --- REGENERATE METADATA ---
    if [ -n "$(ls -A "$ARCH_DIR"/*.rpm 2>/dev/null)" ]; then
        echo "[PUBLISH] Regenerating repository metadata for $arch..."
        createrepo_c "$ARCH_DIR"
    fi
done

# --- PUBLISH PUBLIC KEY ---
gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"
echo "[OK] RPM repository updated successfully."

