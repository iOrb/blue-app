#!/usr/bin/env python3
"""Validate catalog completeness, placeholders, explicit identical translations, and static uses."""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
errors = []
known = set()
identical_allowed = {"no", "app.name"}
for path in (root / "Blue/Resources").glob("*.xcstrings"):
    catalog = json.loads(path.read_text())
    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{path.name}: source language must be en")
    for key, entry in catalog["strings"].items():
        known.add(key)
        if entry.get("extractionState") == "stale":
            errors.append(f"{key}: stale")
        values = []
        for language in ("en", "es"):
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value", "").strip():
                errors.append(f"{key}: missing or untranslated {language}")
            values.append(unit.get("value", ""))
        if values[0] == values[1] and key not in identical_allowed:
            errors.append(f"{key}: identical translation needs an explicit exception")
        pattern = r"%(?:\d+\$)?(?:ld|lld|@|d|f)"
        if sorted(re.findall(pattern, values[0])) != sorted(re.findall(pattern, values[1])):
            errors.append(f"{key}: mismatched format placeholders")
for path in (root / "Blue").rglob("*.swift"):
    source = path.read_text()
    for key in re.findall(r'(?:\bl\(|\.key\(|\.message\(|\.format\()"([^"\\]+)"', source):
        if key not in known:
            errors.append(f"{path.name}: missing key {key}")
    for literal in re.findall(r'\b(?:Text|Button|TextField|Toggle|Picker|Section|Label)\("([^"\\]+)"', source):
        if literal not in {"English", "Español (España)", "•"}:
            errors.append(f"{path.name}: unlocalized UI literal {literal}")
for prefix, values in {
    "template.": ["movies", "tv", "games", "artists", "food", "restaurants", "simple"],
    "field.": ["text", "number", "rating", "date", "status", "checkbox", "like", "favorite", "tags"],
    "character.": ["idle", "listening", "thinking", "searching", "working", "success", "error"],
    "status.": ["wantWatch", "watched", "watching", "finished", "wantPlay", "playing", "wantExplore", "exploring", "wantTry", "tried", "wantVisit", "visited"],
    "error.": ["missing", "ambiguous", "invalidValue", "staleRevision", "folderDepth", "permissionDenied", "alarmFailed", "saveFailed", "modelUnavailable", "cancelled", "unsupported", "emptyTitle", "webUnavailable"],
}.items():
    for value in values:
        if prefix + value not in known:
            errors.append(f"Missing dynamic key {prefix + value}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Localization passed: {len(known)} keys, English and Spanish, matching placeholders.")
