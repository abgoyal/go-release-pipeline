#!/bin/bash
set -eou pipefail
set -x
echo "--- Managing Debian (APT) Repository using Aptly ---"

# --- CONFIGURATION ---
REPO_DIR="gh-pages/deb"
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
cat > "$APTLY_CONFIG" <<EOF
{ "rootDir": "$(pwd)/.aptly", "architectures": ["amd64", "arm64"] }
EOF
#trap 'rm -f -- "$APTLY_CONFIG"' EXIT

# restore repo metadata from ghpages
mkdir -p "$REPO_DIR/metadata" # in case it doesn't exist, the next command should not error out.
mv "$REPO_DIR/metadata/*" "$(pwd)/.aptly/"


# Check if repo exists, create if not
if ! aptly -config="$APTLY_CONFIG" repo show "$REPO_NAME" > /dev/null 2>&1; then
    aptly -config="$APTLY_CONFIG" repo create -distribution="$DISTRIBUTION" -component="$COMPONENT" "$REPO_NAME"
fi

# --- CLEANUP OLD PACKAGES ---
echo "[CLEANUP] Cleaning up old packages from Aptly repository..."
all_packages=$(aptly -config="$APTLY_CONFIG" repo show -with-packages "$REPO_NAME" 2>/dev/null | sed -n '/^Packages:/,$p' | sed '1d; s/^[[:blank:]]*//' || echo "")
if [ -n "$all_packages" ]; then
    current_major=$(echo "${NEW_VERSION#v}" | cut -d. -f1)
    previous_major_num=$((${current_major} - 1))
    previous_major="${previous_major_num}"

    versions=$(echo "$all_packages" | sort -rV | uniq)

    to_keep_current=$(echo "$versions" | grep "^${current_major}" | head -n $KEEP_CURRENT_MAJOR || true)
    to_keep_previous=$(echo "$versions" | grep "^${previous_major}" | head -n $KEEP_PREVIOUS_MAJOR || true)
    to_keep_versions=$(echo -e "${to_keep_current}\n${to_keep_previous}" | sed '/^\s*$/d' | sort | uniq)

    packages_to_remove=""
    for v in $(echo "$versions"); do
        if ! echo "$to_keep_versions" | grep -q "^$v$"; then
            echo "[CLEANUP] Marking version $v for removal."
            packages_to_remove+=$(echo "$all_packages" | grep "_${v}_" | awk '{print " "$1}' || true)
        fi
    done

    if [ -n "$packages_to_remove" ]; then
        # shellcheck disable=SC2086
        aptly -config="$APTLY_CONFIG" repo remove "$REPO_NAME" $packages_to_remove
    fi
else
    echo "[INFO] Aptly repository is new or empty. No cleanup needed."
fi

# --- ADD NEW PACKAGES ---
echo "[ADD] Adding new packages to Aptly repository..."
DEB_FILES=$(find "$ARTIFACTS_DIR" -name "*.deb")
if [ -z "$DEB_FILES" ]; then
    echo "[INFO] No .deb files found in artifacts. Skipping."
    exit 0
fi
aptly -config="$APTLY_CONFIG" repo add "$REPO_NAME" $DEB_FILES

# --- PUBLISH REPO ---
echo "[PUBLISH] Publishing Debian repository..."
aptly -config="$APTLY_CONFIG" publish repo -batch -force-overwrite -component="$COMPONENT" -distribution="$DISTRIBUTION" \
    -gpg-key="$GPG_KEY_ID" -passphrase="$GPG_PASSPHRASE" "$REPO_NAME" .


mkdir -p "$REPO_DIR"
cp -a ".aptly/public/." "$REPO_DIR"

# save repo metadata into the gh_pages, for use next time.
mv  ".aptly/*" "$REPO_DIR/metadata/"

gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"
echo "[OK] Debian repository updated successfully."
