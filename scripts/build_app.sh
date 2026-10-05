#!/bin/sh
# Builds KeepAlive.app into ./build. Usage: scripts/build_app.sh [--universal]
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# Use the full Xcode even if xcode-select points at the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    case "$(xcode-select -p 2>/dev/null)" in
        *.app/Contents/Developer) ;;
        *) [ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
    esac
fi

ARCH_FLAGS=""
if [ "${1:-}" = "--universal" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

APP="$ROOT/build/KeepAlive.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/KeepAlive" "$APP/Contents/MacOS/KeepAlive"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xcrun xcstringstool compile "$ROOT/Resources/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"

# Ad-hoc signature. Without a paid developer account the app cannot be notarized.
codesign --force --sign - --options runtime "$APP"

(cd "$ROOT/build" && rm -f KeepAlive.zip && ditto -c -k --keepParent KeepAlive.app KeepAlive.zip)
echo "Built $APP"
