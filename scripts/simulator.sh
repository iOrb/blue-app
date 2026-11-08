#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
BLUE_RUNTIME="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and r["name"].startswith("iOS") and r["identifier"].split(".")[-1].count("-")==2]; print(sorted(r,key=lambda r:tuple(map(int,r["version"].split("."))))[-1]["identifier"] if r else "")')"
[ -n "$BLUE_RUNTIME" ] || { echo 'Install an iOS simulator runtime in Xcode Settings > Components.' >&2; exit 1; }
BLUE_RUNTIME="${BLUE_RUNTIME_IDENTIFIER:-$BLUE_RUNTIME}"
BLUE_DEVICE_NAME="${BLUE_DEVICE_NAME:-Blue iPhone}"
BLUE_DEVICE_TYPE="${BLUE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
BLUE_SIMULATOR="$(xcrun simctl list devices -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"].get(sys.argv[2],[]); print(next((x["udid"] for x in d if x["name"]==sys.argv[1] and x["isAvailable"]),""))' "$BLUE_DEVICE_NAME" "$BLUE_RUNTIME")"
if [ -z "$BLUE_SIMULATOR" ]; then BLUE_SIMULATOR="$(xcrun simctl create "$BLUE_DEVICE_NAME" "$BLUE_DEVICE_TYPE" "$BLUE_RUNTIME")"; fi
xcrun simctl boot "$BLUE_SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$BLUE_SIMULATOR" -b >&2
export BLUE_SIMULATOR
