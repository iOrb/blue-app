#!/bin/bash
# Xcode Cloud checks the committed project; no package installation or secrets.
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
python3 scripts/check-localization.py
xcrun swift-format lint --strict --recursive Blue BlueTests BlueUITests
for script in scripts/*.sh ci_scripts/*.sh; do bash -n "$script"; done
