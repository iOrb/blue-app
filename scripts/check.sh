#!/bin/bash
source "$(dirname "$0")/env.sh"
python3 scripts/check-localization.py
xcrun swift-format lint --strict --recursive Blue BlueTests BlueUITests > artifacts/format.log 2>&1 || { head -n 60 artifacts/format.log; exit 1; }
python3 -m py_compile scripts/check-localization.py
for script in scripts/*.sh; do bash -n "$script"; done
