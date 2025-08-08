#!/bin/bash
set -euo pipefail
set -x

echo "--- Managing Alpine (APK) Repository ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages"
ARTIFACTS_DIR="artifacts"
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1
ABUILD_KEY_NAME="ci-key"

# --- CHECK REQUIRED TOOLS ---
command -v openssl >/dev/null || { echo "[ERROR] openssl not found"; exit 1; }
command -v abuild-sign >/dev/null || { echo "[ERROR] abuild-sign not found"; exit 1; }
command -v apk >/dev/null || { echo "[ERROR] apk not found"; exit 1; }

# --- SETUP ABUILD KEYS ---
# This key is used for signing both packages and the index.
mkdir -p "$HOME/.abuild"
echo "${APK_PRIVATE_KEY}" > "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
chmod 600 "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
echo "PACKAGER_PRIVKEY=\"$HOME/.abuild/${ABUILD_KEY_NAME}.rsa\"" > "$HOME/.abuild/abuild.conf"

# --- PROCESS EACH ARCHITECTURE ---
for arch_mapping in "amd64:x86_64" "arm64:aarch64"; do
    GORELEASER_ARCH="${arch_mapping%:*}"
    ALPINE_ARCH="${arch_mapping#*:}"

    echo "--- Processing architecture: $ALPINE_ARCH ---"
    ARCH_DIR="$REPO_DIR/$ALPINE_ARCH"
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
            find "$ARCH_DIR" -name "*${v}*${GORELEASER_ARCH}.apk" -exec rm -v {} +
        done
    fi

    # --- ADD & SIGN NEW PACKAGES ---
    for unsigned_apk in $(find "$ARTIFACTS_DIR" -name "*${GORELEASER_ARCH}*.apk" 2>/dev/null); do
        echo "[PROCESS] Processing new package: $(basename "$unsigned_apk")"

        # This rebuild process is CRITICAL. It fixes the artifact from GoReleaser
        # to make it compatible with the official Alpine tools.
        temp_dir=$(mktemp -d)

        # 1. Extract the contents into a temporary directory.
        tar -xzf "$unsigned_apk" -C "$temp_dir"

        # 2. Remove the incorrect datahash line from the .PKGINFO file.
        sed -i '/^datahash =/d' "$temp_dir/.PKGINFO"

        # 3. Define an absolute path for the rebuilt package.
        #    Prepending $PWD is the crucial fix for the "No such file" error,
        #    as it ensures the path is valid even after we 'cd'.
        rebuilt_apk_path="$PWD/$ARCH_DIR/$(basename "$unsigned_apk")"

        # 4. Create the new, clean tarball with correct, root-level paths.
        (cd "$temp_dir" && tar -czf "$rebuilt_apk_path" .PKGINFO usr)

        rm -rf "$temp_dir"

        # 5. Now, sign the correctly rebuilt package.
        echo "[SIGN] Signing $(basename "$rebuilt_apk_path")"
        abuild-sign "$rebuilt_apk_path"
    done

    # --- REGENERATE METADATA ---
    if ls "$ARCH_DIR"/*.apk 1> /dev/null 2>&1; then
        echo "[PUBLISH] Regenerating repository metadata for $ALPINE_ARCH..."
        apk index -o "$ARCH_DIR/APKINDEX.tar.gz" "$ARCH_DIR"/*.apk
        abuild-sign "$ARCH_DIR/APKINDEX.tar.gz"
    fi
done

# --- PUBLISH PUBKEY AT REPO ROOT ---
# Generate the public key from the private key and publish it with the correct name.
openssl rsa -in "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" -pubout > "$REPO_DIR/${ABUILD_KEY_NAME}.rsa.pub"

echo "[OK] Alpine repository updated."
echo "[INFO] Public key is in: $REPO_DIR/${ABUILD_KEY_NAME}.rsa.pub"
