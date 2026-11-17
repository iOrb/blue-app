#!/bin/bash
# Uploads a previously verified archive for INTERNAL TestFlight only.
source "$(dirname "$0")/env.sh"
BLUE_UPLOAD_ARCHIVE="${1:?Usage: scripts/upload-testflight.sh path/to/Blue.xcarchive}"
if [[ ! -d "$BLUE_UPLOAD_ARCHIVE" || "$BLUE_UPLOAD_ARCHIVE" != *.xcarchive ]]; then
    printf 'A valid .xcarchive is required.\n' >&2
    exit 1
fi
xcodebuild -exportArchive -archivePath "$BLUE_UPLOAD_ARCHIVE" \
    -exportOptionsPlist scripts/testflight-export-options.plist \
    -exportPath artifacts/testflight-upload -allowProvisioningUpdates \
    > artifacts/testflight-upload.log 2>&1 || { tail -n 50 artifacts/testflight-upload.log; exit 1; }
printf 'Apple upload command completed. Confirm processing and tester availability in App Store Connect.\n'
