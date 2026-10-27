#!/bin/sh
# Prints the description for a GitHub release.
# Usage: scripts/release_notes.sh v1.2 [path/to/KeepAlive.zip]
#
# Uses the matching section of CHANGELOG.md. Without one, it lists the commits since
# the previous tag. Installation steps, requirements and the checksum follow.
set -eu

cd "$(dirname "$0")/.."

TAG="${1:?usage: scripts/release_notes.sh <tag> [zip]}"
ZIP="${2:-}"
VERSION="${TAG#v}"
REPO="${GITHUB_REPOSITORY:-oli-zr/keepalive}"

# Everything between "## [VERSION]" and the next "## " heading.
NOTES="$(awk -v version="$VERSION" '
    /^## / {
        if (found) exit
        if (index($0, "## [" version "]") == 1) { found = 1; next }
    }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [ -z "$NOTES" ]; then
    PREVIOUS="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
    RANGE="${PREVIOUS:+$PREVIOUS..}$TAG"
    NOTES="### Changes

$(git log --no-merges --format='- %s' "$RANGE")"
fi

printf '%s\n' "$NOTES"

cat <<EOF

### Installation

Open Terminal, paste this line and press Return:

\`\`\`sh
curl -fsSL https://github.com/$REPO/raw/main/scripts/install.sh | sh
\`\`\`

It installs or updates KeepAlive and opens it. Then follow the
[setup guide](https://github.com/$REPO#setup) to add your apps. To install without
Terminal, see [the other ways](https://github.com/$REPO#installation).

KeepAlive 1.1 and later install updates by themselves. Your settings are kept.

**Requirements:** macOS 14 or later, Xcode 15 or later, an iPhone or iPad with Developer Mode.
EOF

if [ -n "$ZIP" ] && [ -f "$ZIP" ]; then
    # The backticks are Markdown, not a command substitution.
    # shellcheck disable=SC2016
    printf '\nSHA-256 of KeepAlive.zip: `%s`\n' "$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
fi
