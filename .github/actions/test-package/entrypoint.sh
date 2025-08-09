#!/bin/bash
set -e

# This script acts as a router to the specific test script.
echo "--- Starting test for $DISTRO on $ARCH ---"

# Get the directory where this script itself is located.
SCRIPT_DIR=$(dirname "$0")

case "$DISTRO" in
    ubuntu)
        "$SCRIPT_DIR/test-deb.sh"
        ;;
    fedora)
        "$SCRIPT_DIR/test-rpm.sh"
        ;;
    alpine)
        "$SCRIPT_DIR/test-apk.sh"
        ;;
    *)
        echo "Error: Unknown distribution '$DISTRO'"
        exit 1
        ;;
esac

echo "--- Test successful for $DISTRO on $ARCH ---"

