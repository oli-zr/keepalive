#!/bin/sh
# Installs or updates KeepAlive from the latest GitHub release.
# Usage: curl -fsSL https://raw.githubusercontent.com/oli-zr/keepalive/main/scripts/install.sh | sh
#
# Downloads KeepAlive.zip, checks it against the published checksum and its signature,
# moves KeepAlive to the Applications folder and opens it. Files downloaded with curl
# are not quarantined, so macOS opens KeepAlive without asking to allow it first.
set -eu

RELEASE="https://github.com/oli-zr/keepalive/releases/latest/download"

# Messages follow the language of the Mac: German or English.
case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)" in
    *de*) GERMAN=1 ;;
    *) GERMAN=0 ;;
esac

say() {
    if [ "$GERMAN" = 1 ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}

fail() {
    say "$1" "$2" >&2
    exit 1
}

# Like KeepAlive itself: the selected Xcode, or any Xcode in /Applications.
has_xcode() {
    xcode-select -p 2>/dev/null | grep -q '\.app/Contents/Developer' && return 0
    for xcode in /Applications/Xcode*.app; do
        [ -x "$xcode/Contents/Developer/usr/bin/xcodebuild" ] && return 0
    done
    return 1
}

# Everything runs from main, so a download that breaks off halfway does nothing.
main() {
    [ "$(uname -s)" = Darwin ] || fail "KeepAlive runs on macOS only." "KeepAlive läuft nur unter macOS."
    major=$(sw_vers -productVersion | cut -d . -f 1)
    [ "$major" -ge 14 ] || fail "KeepAlive needs macOS 14 Sonoma or later." "KeepAlive braucht macOS 14 Sonoma oder neuer."

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    say "Downloading KeepAlive…" "KeepAlive wird geladen …"
    curl -fsSL "$RELEASE/KeepAlive.zip" -o "$work/KeepAlive.zip" \
        || fail "The download failed. Check your internet connection and try again." \
                "Der Download ist fehlgeschlagen. Prüfe deine Internetverbindung und versuche es erneut."
    curl -fsSL "$RELEASE/KeepAlive.zip.sha256" -o "$work/KeepAlive.zip.sha256" \
        || fail "The download failed. Check your internet connection and try again." \
                "Der Download ist fehlgeschlagen. Prüfe deine Internetverbindung und versuche es erneut."

    expected=$(tr -d '[:space:]' < "$work/KeepAlive.zip.sha256")
    actual=$(shasum -a 256 "$work/KeepAlive.zip" | cut -d ' ' -f 1)
    [ "$expected" = "$actual" ] \
        || fail "The download is damaged. Nothing was installed. Please try again." \
                "Der Download ist beschädigt. Es wurde nichts installiert. Bitte versuche es erneut."

    ditto -x -k "$work/KeepAlive.zip" "$work/unpacked"
    app="$work/unpacked/KeepAlive.app"
    codesign --verify --deep --strict "$app" 2>/dev/null \
        || fail "The downloaded app is not intact. Nothing was installed." \
                "Die geladene App ist nicht intakt. Es wurde nichts installiert."

    # /Applications needs an administrator account; otherwise use the personal Applications folder.
    if [ -w /Applications ]; then
        folder=/Applications
    else
        folder="$HOME/Applications"
        mkdir -p "$folder"
    fi
    target="$folder/KeepAlive.app"

    if [ -d "$target" ]; then
        say "Replacing the installed KeepAlive. Your apps and settings are kept." \
            "Das installierte KeepAlive wird ersetzt. Deine Apps und Einstellungen bleiben erhalten."
        if pkill -x KeepAlive 2>/dev/null; then sleep 1; fi
    fi
    rm -rf "$target.new" "$target.old"
    ditto "$app" "$target.new"
    if [ -d "$target" ]; then mv "$target" "$target.old"; fi
    mv "$target.new" "$target"
    rm -rf "$target.old"
    xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

    version=$(defaults read "$target/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
    say "KeepAlive $version is installed in $folder." "KeepAlive $version ist in $folder installiert."

    if ! has_xcode; then
        say "" ""
        say "KeepAlive needs Xcode, which was not found. Install it from the App Store:" \
            "KeepAlive braucht Xcode, das nicht gefunden wurde. Installiere es aus dem App Store:"
        say "https://apps.apple.com/app/xcode/id497799835" "https://apps.apple.com/app/xcode/id497799835"
    fi

    open "$target"
    say "" ""
    say "KeepAlive is now in your menu bar. Next steps: https://github.com/oli-zr/keepalive#setup" \
        "KeepAlive ist jetzt in deiner Menüleiste. So geht es weiter: https://github.com/oli-zr/keepalive/blob/main/README.de.md#einrichtung"
}

main "$@"
