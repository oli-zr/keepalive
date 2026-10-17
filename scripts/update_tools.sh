#!/bin/sh
# Updates .github/ci.env to the newest Xcode runner image, actionlint and shellcheck.
# Prints a Markdown list of what changed, or nothing when everything is up to date.
# The Update tools workflow runs it every week. Usage: scripts/update_tools.sh
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=.github/ci.env

fail() { echo "error: $*" >&2; exit 1; }

# Newest release of a GitHub repository, from tags such as v1.7.12.
latest_release() {
    git ls-remote --tags --refs "https://github.com/$1" \
        | sed -n 's#.*refs/tags/v\([0-9][0-9.]*\)$#\1#p' | sort -V | tail -n 1
}

# Newest Xcode image for GitHub-hosted runners, from tags such as xcode-27-arm64/20260907.0173.
# GitHub names these images after the Xcode version, one Xcode per image.
latest_xcode_runner() {
    git ls-remote --tags --refs https://github.com/actions/runner-images \
        | sed -n 's#.*refs/tags/\(xcode-[0-9][0-9]*\)-arm64/.*#\1#p' | sort -V | tail -n 1
}

# Sets KEY to VALUE and prints the change. Only ever moves to a higher version.
update() {
    key="$1" new="$2"
    [ -n "$new" ] || fail "Could not find the newest $key."
    old="$(sed -n "s/^$key=//p" "$ENV_FILE")"
    [ -n "$old" ] || fail "$ENV_FILE has no $key."
    [ "$old" = "$new" ] && return 0
    [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -n 1)" = "$new" ] || return 0
    sed "s/^$key=.*/$key=$new/" "$ENV_FILE" > "$ENV_FILE.new" && mv "$ENV_FILE.new" "$ENV_FILE"
    echo "- \`$key\`: $old → $new"
}

update XCODE_RUNNER "$(latest_xcode_runner)"
update ACTIONLINT_VERSION "$(latest_release rhysd/actionlint)"
update SHELLCHECK_VERSION "$(latest_release koalaman/shellcheck)"
