#!/bin/bash
source "$(dirname "$0")/env.sh"
xcrun swiftc -O -parse-as-library -swift-version 6 -strict-concurrency=complete \
  Blue/Domain/*.swift Blue/Data/LibraryStore.swift Blue/Localization/Localizer.swift \
  Blue/Services/AssistantService.swift Blue/Services/CollectionQueryTool.swift \
  Blue/Services/AdaptiveCollectionTools.swift Blue/Services/PublicFactsService.swift Blue/Services/ModifyCollectionTool.swift Blue/Services/SemanticLibraryTools.swift \
  scripts/model-integration-mac.swift -o artifacts/blue-model-integration
python3 scripts/prepare-model-resources.py artifacts
artifacts/blue-model-integration | tee artifacts/production-model-mac.log
