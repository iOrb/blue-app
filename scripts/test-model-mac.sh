#!/bin/bash
source "$(dirname "$0")/env.sh"
xcrun swiftc -O -parse-as-library -swift-version 6 -strict-concurrency=complete \
  Blue/Domain/*.swift Blue/Data/LibraryStore.swift Blue/Localization/Localizer.swift \
  Blue/Services/AssistantService.swift Blue/Services/CollectionQueryTool.swift \
  scripts/model-integration-mac.swift -o artifacts/blue-model-integration
artifacts/blue-model-integration | tee artifacts/production-model-mac.log
