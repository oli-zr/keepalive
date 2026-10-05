#!/bin/sh
# Builds KeepAlive.app into ./build. Usage: scripts/build_app.sh [--universal]
# On GitHub Actions, a version tag such as v1.2 sets the app's version number.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

fail() { echo "error: $*" >&2; exit 1; }

# Use the full Xcode even if xcode-select points at the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    case "$(xcode-select -p 2>/dev/null)" in
        *.app/Contents/Developer) ;;
        *) [ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
    esac
fi

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[ "${SDK_VERSION%%.*}" -ge 26 ] || fail "Xcode 26 or later is required (found macOS SDK $SDK_VERSION)."

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

# SwiftPM records the deployment target as the SDK version. macOS uses that SDK version
# to decide whether an app gets the current design (Liquid Glass) or the compatibility
# look, so record the SDK that was actually used.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/Resources/Info.plist")"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/KeepAlive" "$APP/Contents/MacOS/KeepAlive"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
case "${GITHUB_REF_NAME:-}" in
    v[0-9]*)
        VERSION="${GITHUB_REF_NAME#v}"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP/Contents/Info.plist"
        ;;
esac

# Liquid Glass icon for macOS 26 and later, plus a classic .icns for older systems.
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$MIN_OS" --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/AppIcon-partial.plist" >/dev/null
[ -f "$APP/Contents/Resources/Assets.car" ] && [ -f "$APP/Contents/Resources/AppIcon.icns" ] \
    || fail "The app icon was not compiled."

xcrun xcstringstool compile "$ROOT/Resources/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"

# Ad-hoc signature. Without a paid developer account the app cannot be notarized.
codesign --force --sign - --options runtime "$APP"

(cd "$ROOT/build" && rm -f KeepAlive.zip && ditto -c -k --keepParent KeepAlive.app KeepAlive.zip)
echo "Built $APP"
