# Blue

A quiet home for Markdown notes, adaptable collections, and a calendar. This repository starts with the native iPhone app, built with SwiftUI, SwiftData, Foundation Models and AlarmKit, and leaves room for future platforms. English and Spanish (Spain). Your library and inference stay local; optional public facts come from Wikipedia with source links.

<p>
  <img src="docs/screenshots/library-en.png" width="230" alt="Blue library in English">
  <img src="docs/screenshots/custom-indicators.png" width="230" alt="Custom visual indicators in collection rows and filters">
  <img src="docs/screenshots/compact-calendar-es.png" width="230" alt="Blue calendar">
</p>

## Run locally

Requires Xcode 27.1 or later with an iOS simulator runtime; verified toolchain details are in [verification](docs/verification.md). The checked-in Xcode project opens directly:

```sh
open Blue.xcodeproj
scripts/build.sh Debug
scripts/run.sh
```

On Xcode 27, the simulator opens in Device Hub. Scripts select the Xcode developer directory per process. They do not modify your global `xcode-select` setting. Regenerate the project with XcodeGen 2.46.0 after changing `project.yml`.

```sh
scripts/check.sh
scripts/test.sh
scripts/build.sh Release
scripts/build-device.sh
scripts/test-model-mac.sh
BLUE_REAL_MODEL_TESTS=1 scripts/test.sh -only-testing:BlueTests/RealModelTests
scripts/profile.sh
```

The normal test suite uses isolated demo data, Swift Testing business/persistence tests, and XCTest UI flows. Real-model checks are opt-in and require Apple Intelligence availability. See the verification report for actual results and limits.

## Try it

Start with a note or an empty collection, or tell Blue what to save. Existing collections remain editable. Bottom navigation opens Notes, Collections, Calendar or Blue. The brand opens the combined view, with the calendar below the notes. Use the plus button for a note, collection, item or calendar event. Collections gain useful typed properties through conversation. Ask Blue to add indicators with your own meaning, icon and color, or to change a collection icon. The same icons work in rows, detail and filters. Saved notes open as rendered Markdown; tap the content to edit; valid changes save automatically. Change language in Settings without losing an open draft. Export your library as versioned JSON from Settings.

With Apple Intelligence ready, ask “What rating did I give Interstellar?”, see the exact saved values in the assistant sheet, then ask “Change Interstellar's rating to 10.” Blue validates and saves through the same store used by the editors. Without a local model, manual controls remain available and the assistant explains its availability. The iPhone 13 mini does not support Apple Intelligence; the private web preview can use the Mac model. All deletions require confirmation. There is no Undo control.

## Install on your iPhone

Open the project in Xcode, choose your free **Personal Team**, connect the iPhone, and press **⌘R**. No paid Developer Program, App Store Connect, TestFlight, or distribution credentials are needed. [Personal Team setup and device checks](docs/release.md) explains signing, Developer Mode and the seven-day provisioning limit.

If the simulator cannot load Apple's model assets but the Mac model is available, use the explicit local development bridge:

```sh
scripts/start-model-bridge.sh
scripts/run.sh
# Opt-in simulator UI check with the real Mac model:
scripts/test-bridge.sh
# Stop the helper when finished:
launchctl remove app.iorb.blue.model-bridge
```

Settings identifies the Mac bridge. It uses real Apple Intelligence, runs only on loopback, and is absent from iPhone/Release builds. Simulator alarms still need hardware verification. Tap the microphone for on-device dictation when available; Enter sends and tapping outside dismisses chat.

The repository is public. GitHub Actions runs formatting, localization, simulator tests and a Release compile; it does not publish or distribute builds.

- [Engineering rules](AGENTS.md)
- [Architecture and privacy](docs/architecture.md)
- [Design rationale](docs/design.md)
- [Verification and known limitations](docs/verification.md)
