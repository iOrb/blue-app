#!/bin/bash
export BLUE_DEVICE_NAME="${BLUE_DEVICE_NAME:-Blue Verification}"
source "$(dirname "$0")/simulator.sh"
[ -f .build/model-bridge-token ] || { echo 'Start scripts/start-model-bridge.sh first.' >&2; exit 1; }
scripts/build.sh Debug
xcrun simctl install "$BLUE_SIMULATOR" .build/Build/Products/Debug-iphonesimulator/Blue.app
BLUE_APP_DATA="$(xcrun simctl get_app_container "$BLUE_SIMULATOR" app.iorb.blue.ios data)"
mkdir -p "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment"
cp .build/model-bridge-token "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment/model-bridge-token"
chmod 600 "$BLUE_APP_DATA/Library/Application Support/BlueDevelopment/model-bridge-token"
BLUE_REAL_BRIDGE_TESTS=1 scripts/test.sh -only-testing:BlueUITests/RealBridgeUITests
