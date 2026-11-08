#!/bin/bash
source "$(dirname "$0")/env.sh"
mkdir -p .build
if [ -f .build/model-bridge.pid ] && kill -0 "$(cat .build/model-bridge.pid)" 2>/dev/null; then
    echo 'Local model bridge is already running.'
    exit 0
fi
xcrun swiftc -O -parse-as-library -swift-version 6 -strict-concurrency=complete \
  Blue/Domain/*.swift Blue/Data/LibraryStore.swift Blue/Localization/Localizer.swift \
  Blue/Services/AssistantService.swift Blue/Services/CollectionQueryTool.swift \
  Blue/Services/AdaptiveCollectionTools.swift Blue/Services/PublicFactsService.swift Blue/Services/ModifyCollectionTool.swift Blue/Services/SemanticLibraryTools.swift \
  Blue/Services/SimulatorModelBridge.swift scripts/model-bridge-mac.swift -o .build/blue-model-bridge
python3 scripts/prepare-model-resources.py .build
umask 077
uuidgen > .build/model-bridge-token
launchctl remove app.iorb.blue.model-bridge 2>/dev/null || true
launchctl submit -l app.iorb.blue.model-bridge -o "$BLUE_ROOT/artifacts/model-bridge.log" -e "$BLUE_ROOT/artifacts/model-bridge.log" -- /bin/bash "$BLUE_ROOT/scripts/run-model-bridge.sh"
echo 'Started the Mac model on loopback for the Debug simulator. No cloud inference.'
