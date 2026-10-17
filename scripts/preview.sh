#!/bin/sh
# Shows a part of KeepAlive with sample data, for checking the design and taking screenshots.
# Usage: scripts/preview.sh [window|settings|menu|general|apps|device|activity]
#
# Runs a real app bundle, because `swift run` records macOS 14 as the SDK and so gets the
# compatibility look instead of the current design (Liquid Glass). Nothing is renewed and
# no settings are written.
set -eu

cd "$(dirname "$0")/.."

TARGET="${1:-window}"
case "$TARGET" in
    window|settings|menu|general|apps|device|activity) ;;
    *) echo "usage: scripts/preview.sh [window|settings|menu|general|apps|device|activity]" >&2; exit 1 ;;
esac

scripts/build_app.sh --debug
KEEPALIVE_PREVIEW="$TARGET" exec build/KeepAlive.app/Contents/MacOS/KeepAlive
