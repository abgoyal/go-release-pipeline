#!/bin/bash
set -euo pipefail
set -x

echo "--- Managing Alpine (APK) Repository ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/apk"
ARTIFACTS_DIR="artifacts"
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1

# --- CHECK REQUIRED TOOLS ---
command -v openssl >/dev/null || { echo "[ERROR] openssl not found"; exit 1; }
command -v abuild-sign >/dev/null || { echo "[ERROR] abuild-sign not found"; exit 1; }
command -v apk >/dev/null || { echo "[ERROR] apk not found"; exit 1; }

# --- SETUP ABUILD KEYS ---
mkdir -p "$HOME/.abuild"
echo "${APK_PRIVATE_KEY}" > "$HOME/.abuild/${APK_KEY_NAME}.rsa"
chmod 600 "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa"
#echo "PACKAGER_PRIVKEY=\"$HOME/.abuild/${ABUILD_KEY_NAME}.rsa\"" > "$HOME/.abuild/abuild.conf"

mkdir -p /etc/apk/keys/
openssl rsa -in "$HOME/.abuild/${ABUILD_KEY_NAME}.rsa" -pubout > "/etc/apk/keys/${APK_KEY_NAME}.rsa.pub"

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
    for signed_apk in $(find "$ARTIFACTS_DIR" -name "*${GORELEASER_ARCH}*.apk" 2>/dev/null); do
        echo "[PROCESS] Processing new package: $(basename "$signed_apk")"
        #temp_dir=$(mktemp -d)
        #tar -xzf "$unsigned_apk" -C "$temp_dir"
        #sed -i '/^datahash =/d' "$temp_dir/.PKGINFO"

        #rebuilt_apk_path="$PWD/$ARCH_DIR/$(basename "$unsigned_apk")"

        original_filename=$(basename "$signed_apk")
        # Assumes filename format is <name>_<version>_<os>_<arch>.apk
        pkg_name=$(echo "$original_filename" | cut -d'_' -f1)
        pkg_ver=$(echo "$original_filename" | cut -d'_' -f2)

        # Construct the standard APK filename that the 'apk' client expects.
        standard_apk_name="${pkg_name}-${pkg_ver}.apk"
        echo "[INFO] Renaming to standard format: ${standard_apk_name}"

        # Use the new, standard name for the final path.
        rebuilt_apk_path="$PWD/$ARCH_DIR/${standard_apk_name}"
        mv "$signed_apk" "$rebuilt_apk_path"
        #(cd "$temp_dir" && tar -czf "$rebuilt_apk_path" .PKGINFO usr)

        #rm -rf "$temp_dir"

        #echo "[SIGN] Signing $(basename "$rebuilt_apk_path")"
        #abuild-sign "$rebuilt_apk_path"
    done

    # --- REGENERATE METADATA ---
    if ls "$ARCH_DIR"/*.apk 1> /dev/null 2>&1; then
        echo "[PUBLISH] Regenerating repository metadata for $ALPINE_ARCH..."
        apk index -o "$ARCH_DIR/APKINDEX.tar.gz" "$ARCH_DIR"/*.apk
        abuild-sign "$ARCH_DIR/APKINDEX.tar.gz"
    fi
done

# --- PUBLISH PUBKEY AT REPO ROOT ---
# Copy the trusted key to the final repository for end-users.
cp "/etc/apk/keys/${APK_KEY_NAME}.rsa.pub" "$REPO_DIR/${APK_KEY_NAME}.rsa.pub"

echo "[OK] Alpine repository updated."
echo "[INFO] Public key is in: $REPO_DIR/${APK_KEY_NAME}.rsa.pub"
