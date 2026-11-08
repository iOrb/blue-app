#!/bin/bash
source "$(dirname "$0")/simulator.sh"
[ -d .build/Build/Products/Debug-iphonesimulator/Blue.app ] || scripts/build.sh Debug
xcrun simctl install "$BLUE_SIMULATOR" .build/Build/Products/Debug-iphonesimulator/Blue.app
xcrun simctl launch "$BLUE_SIMULATOR" app.iorb.blue.ios
BLUE_DEVICE_HUB="$DEVELOPER_DIR/../Applications/DeviceHub.app"
if [ -d "$BLUE_DEVICE_HUB" ]; then
    open -a "$BLUE_DEVICE_HUB"
else
    open -a "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$BLUE_SIMULATOR"
fi
