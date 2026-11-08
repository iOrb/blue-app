#!/usr/bin/env python3
"""Build catalog resources next to standalone Mac verification executables."""
import json
import plistlib
import sys
from pathlib import Path

catalog = json.loads(Path('Blue/Resources/Localizable.xcstrings').read_text())
for language in ('en', 'es'):
    values = {
        key: entry['localizations'][language]['stringUnit']['value']
        for key, entry in catalog['strings'].items()
    }
    directory = Path(sys.argv[1]) / f'{language}.lproj'
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'Localizable.strings').write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
