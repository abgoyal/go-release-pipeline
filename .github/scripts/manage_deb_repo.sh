#!/bin/bash
set -eou pipefail
set -x
echo "--- Managing Debian (APT) Repository using Aptly ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/deb"
APTLY_HOME="$HOME/aptly_metadata"
ARTIFACTS_DIR="artifacts"
COMPONENT="main"
DISTRIBUTION="."
KEEP_CURRENT_MAJOR=5
KEEP_PREVIOUS_MAJOR=1

# --- GPG SETUP ---
GPG_HOME=$(mktemp -d)
trap 'rm -rf -- "$GPG_HOME"' EXIT
chmod 700 "$GPG_HOME"
export GNUPGHOME="$GPG_HOME"

echo "${GPG_PRIVATE_KEY}" | gpg --batch --import
GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format long | grep 'sec ' | awk '{print $2}' | cut -d'/' -f2)

# --- APTLY SETUP ---
APTLY_CONFIG=$(mktemp)
mkdir -p "$APTLY_HOME"
cat > "$APTLY_CONFIG" <<EOF
{ "rootDir": "$APTLY_HOME", "architectures": ["amd64", "arm64"] }
EOF
#trap 'rm -f -- "$APTLY_CONFIG"' EXIT

# Check if repo exists, create if not
#if ! aptly -config="$APTLY_CONFIG" repo show "$REPO_NAME" > /dev/null 2>&1; then
    aptly -config="$APTLY_CONFIG" repo create -distribution="$DISTRIBUTION" -component="$COMPONENT" "$REPO_NAME"
#fi


# --- PROCESS EACH ARCHITECTURE ---
for ARCH in "amd64" "arm64"; do
    echo "--- Processing architecture: $ARCH ---"

    # --- CLEANUP OLD PACKAGES ---
    echo "[CLEANUP] Cleaning up old packages in $REPO_DIR..."
    versions=$(find "$REPO_DIR/pool" -name "*${ARCH}*.deb" -exec basename {} \; | \
               grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -rV | uniq || true)

    if [ -n "$versions" ]; then
        current_major=$(echo "${NEW_VERSION#v}" | cut -d. -f1)
        previous_major_num=$((${current_major} - 1))
        previous_major="${previous_major_num}"

        to_keep_current=$(echo "$versions" | grep "^$current_major" | head -n $KEEP_CURRENT_MAJOR || true)
        to_keep_previous=$(echo "$versions" | grep "^$previous_major" | head -n $KEEP_PREVIOUS_MAJOR || true)
        to_keep=$(echo -e "${to_keep_current}\n${to_keep_previous}" | sed '/^\s*$/d' | sort -rV | uniq)
        #to_delete=$(comm -23 <(echo "$versions" | sort -rV) <(echo "$to_keep" | sort -rV))

        for v in $to_keep; do
            echo "[ADD] Adding old deb files to repo for $v"

            find "$REPO_DIR/pool" -name "*${v}*${ARCH}.deb"
            find "$REPO_DIR/pool" -name "*${v}*${ARCH}.deb" -exec aptly -config="$APTLY_CONFIG" repo add "$REPO_NAME"  {} + || true
        done
    fi

    # --- ADD NEW PACKAGES ---
    echo "[ADD] Adding new packages to Aptly repository..."
    DEB_FILES=$(find "$ARTIFACTS_DIR" -name "*${ARCH}*.deb")
    if [ -z "$DEB_FILES" ]; then
      echo "[INFO] No .deb files found in artifacts. Skipping."
      exit 0
    fi
    aptly -config="$APTLY_CONFIG" repo add "$REPO_NAME" $DEB_FILES

done

# --- PUBLISH REPO ---
echo "[PUBLISH] Publishing Debian repository..."
aptly -config="$APTLY_CONFIG" publish snapshot -batch -force-overwrite -component="$COMPONENT" -distribution="$DISTRIBUTION" \
    -gpg-key="$GPG_KEY_ID" -passphrase="$GPG_PASSPHRASE" "$REPO_NAME" .


mkdir -p "$REPO_DIR"
# copy the generated repo static assets to repo root
cp -a "$APTLY_HOME/public/." "$REPO_DIR"

gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"
echo "[OK] Debian repository updated successfully."
