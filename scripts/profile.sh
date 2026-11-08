#!/bin/bash
source "$(dirname "$0")/simulator.sh"
BLUE_RESULTS="artifacts/Performance-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Release -destination "platform=iOS Simulator,id=$BLUE_SIMULATOR" -derivedDataPath .build-profile -resultBundlePath "$BLUE_RESULTS" -parallel-testing-enabled NO -enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PERFORMANCE_PROBE' test -only-testing:BlueUITests/PerformanceTests -only-testing:BlueTests/QueryPerformanceTests > artifacts/performance.log 2>&1 || { tail -n 70 artifacts/performance.log; exit 1; }
rg 'measured|QUERY_BASELINE|Test Case.*passed|TEST SUCCEEDED' artifacts/performance.log
