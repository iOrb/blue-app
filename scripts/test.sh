#!/bin/bash
source "$(dirname "$0")/simulator.sh"
BLUE_RESULTS="artifacts/Tests-$(date +%Y%m%d-%H%M%S).xcresult"
BLUE_TEST_FLAGS=(-skip-testing:BlueUITests/PerformanceTests -skip-testing:BlueTests/QueryPerformanceTests)
if [ "${BLUE_REAL_MODEL_TESTS:-0}" != 1 ]; then BLUE_TEST_FLAGS+=(-skip-testing:BlueTests/RealModelTests); fi
if [ "${BLUE_REAL_BRIDGE_TESTS:-0}" != 1 ]; then BLUE_TEST_FLAGS+=(-skip-testing:BlueUITests/RealBridgeUITests); fi
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Debug -destination "platform=iOS Simulator,id=$BLUE_SIMULATOR" -derivedDataPath .build -resultBundlePath "$BLUE_RESULTS" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test "${BLUE_TEST_FLAGS[@]}" "$@" > artifacts/tests.log 2>&1 || { tail -n 100 artifacts/tests.log; exit 1; }
tail -n 20 artifacts/tests.log
