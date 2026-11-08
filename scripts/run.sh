#!/bin/bash
source "$(dirname "$0")/simulator.sh"
[ -d .build/Build/Products/Debug-iphonesimulator/Blue.app ] || scripts/build.sh Debug
xcrun simctl install "$BLUE_SIMULATOR" .build/Build/Products/Debug-iphonesimulator/Blue.app
if [ -f .build/model-bridge-token ] && [ -f .build/model-bridge.pid ] && kill -0 "$(cat .build/model-bridge.pid)" 2>/dev/null; then
    BLUE_APP_DATA="$(xcrun simctl get_app_container "$BLUE_SIMULATOR" app.iorb.blue.ios data)"
    mkdir -p "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment"
    cp .build/model-bridge-token "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment/model-bridge-token"
    chmod 600 "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment/model-bridge-token"
    SIMCTL_CHILD_BLUE_MODEL_BRIDGE_TOKEN="$(cat .build/model-bridge-token)" xcrun simctl launch "$BLUE_SIMULATOR" app.iorb.blue.ios
else
    xcrun simctl launch "$BLUE_SIMULATOR" app.iorb.blue.ios
fi
BLUE_DEVICE_HUB="$DEVELOPER_DIR/../Applications/DeviceHub.app"
if [ -d "$BLUE_DEVICE_HUB" ]; then
    open -a "$BLUE_DEVICE_HUB"
else
    open -a "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$BLUE_SIMULATOR"
fi
