#!/bin/bash
# Creates a local archive; deliberately does not upload or install it.
source "$(dirname "$0")/env.sh"
BLUE_ARCHIVE="artifacts/Blue-$(date +%Y%m%d-%H%M%S).xcarchive"
BLUE_ARCHIVE_TEAM="${BLUE_TEAM_ID:-Z33UY64QQA}"
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$BLUE_ARCHIVE" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$BLUE_ARCHIVE_TEAM" \
    archive > artifacts/archive.log 2>&1 || { tail -n 60 artifacts/archive.log; exit 1; }
BLUE_ARCHIVED_INFO="$BLUE_ARCHIVE/Products/Applications/Blue.app/Info.plist"
BLUE_ARCHIVED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$BLUE_ARCHIVED_INFO")"
BLUE_ARCHIVED_BUILD="$(plutil -extract CFBundleVersion raw "$BLUE_ARCHIVED_INFO")"
printf 'Archive ready: %s (version %s, build %s)\n' "$BLUE_ARCHIVE" "$BLUE_ARCHIVED_VERSION" "$BLUE_ARCHIVED_BUILD"
