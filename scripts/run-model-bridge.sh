#!/bin/bash
source "$(dirname "$0")/env.sh"
export BLUE_MODEL_BRIDGE_TOKEN="$(cat .build/model-bridge-token)"
echo "$$" > .build/model-bridge.pid
exec .build/blue-model-bridge
