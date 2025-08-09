#!/bin/bash
set -e

# This script acts as a router to the specific test script.
echo "--- Starting test for $DISTRO on $ARCH ---"

case "$DISTRO" in
    ubuntu)
        /test-deb.sh
        ;;
    fedora)
        /test-rpm.sh
        ;;
    alpine)
        /test-apk.sh
        ;;
    *)
        echo "Error: Unknown distribution '$DISTRO'"
        exit 1
        ;;
esac

echo "--- Test successful for $DISTRO on $ARCH ---"

