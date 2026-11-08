# Blue engineering rules

## Product and toolchain
- Current delivery: public `iOrb/blue-app`, local simulator, and direct Xcode installation with a free Personal Team. The repository name supports future platforms; this implementation is native iOS. Do not add TestFlight, App Store Connect, paid membership, or distribution secrets. These user decisions override the original distribution brief.
- Native iPhone app; minimum iOS 26.0. Local toolchain: Xcode 27.2 (27B52), Swift 6.4.2, macOS 26.6.2 on Apple silicon. Use Swift 6 language mode and complete concurrency checks.
- The latest user direction overrides the starter brief: only notes, collections and calendar; no combined Your Space view. Remove the folder UI and flatten legacy folders while preserving every collection and note. No predefined creation templates. New libraries start empty; demo templates are test fixtures only. Use compact, icon-based controls and show every saved property, including favorites. Custom indicators have a user-defined meaning, emoji/SF Symbol and color shared by rows and details. Inactive indicators are light gray; active indicators are filled with their color. Notes show only an editable title and plain text with line breaks. Preserve existing stored text. Filters are controlled through Blue, without manual icon-filter controls. AI can edit notes, add/remove fields and change collection/property icons; stage removal of nonempty fields for review. Ship English (default) and Spanish (Spain).
- The assistant is the primary capture and adaptation path: support generic records, inferred collections, requested fields and sourced basic web enrichment. Keep manual editing simple. Enter sends, tapping outside dismisses chat without consuming navigation, and microphone dictation is explicit.
- Preserve user data and drafts. Prefer one complete, verified flow over decorative controls. Never claim an alarm or edit succeeded before the platform/store confirms it.
- This file follows [Codex project instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md). Do not introduce delegation requirements or account approval gates here.

## Ownership and dependency direction
- `Blue/App`: composition, navigation, settings. Depends on Features, Services, Data, Domain.
- `Blue/Features/{Library,Collections,Notes,Assistant,Calendar}`: SwiftUI presentation and local drafts; use the store for mutations. No direct cross-feature persistence.
- `Blue/Domain`: Codable, Sendable values, validation, typed queries, templates; Foundation only. No UI, persistence, or model imports.
- `Blue/Data`: SwiftData versioned schema and transactional store; depends only on Domain and localization.
- `Blue/Services`: Foundation Models tools, AlarmKit adapter, export; depend on Domain/Data, never feature views.
- `Blue/Design` and `Blue/Localization`: shared presentation and string catalog access. `BlueTests` uses Swift Testing; `BlueUITests` uses XCTest. `scripts` owns reproducible build, run and verification commands.
- `project.yml` is the source of truth for the checked-in Xcode project. No runtime third-party dependencies.

## Implementation rules
- Use stable UUIDs, semantic field IDs, typed values, explicit store saves and rollback on failure. Never reseed an existing store. Schema changes require an explicit migration. See [SwiftData](https://developer.apple.com/documentation/swiftdata).
- UI/store operations are MainActor isolated. Tools use Sendable argument/result values, bounded context, cancellation and a per-request mutation ledger. Do not suppress concurrency diagnostics with unsafe annotations.
- On-device inference only via [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel). Manual actions remain available without a model. Tools validate IDs, revisions, field types and input limits. Ask for ambiguous identity; stage destructive changes for confirmation. Test doubles are DEBUG-only and explicitly identified.
- System alarms use [AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit). Store enabled state only after scheduling succeeds; reconcile with system changes. No simulated production alarms or silent fallback to notifications.
- String catalogs are the source of truth. Resolve every app-owned string through the selected locale; preserve user-authored text and view identity when switching. Permission UI follows system language. See [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog).
- Follow [Apple lists guidance](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): compact text rows, no spreadsheet or horizontal scroll. Heart = like; star = favorite; rating = numeric. Hide empty optional fields. Status choices, numeric ranges and toggles match field meaning. Blue can apply and clear collection queries. Collection back/options stay fixed while the centered title, count and sort row scroll. Tapping the active sort criterion reverses direction. Detail sheets have a down-chevron and options menu; delete is a red minus at the bottom of the menu. Deletion uses a centered modal with a floating top-right cross. Hide section navigation inside collections and sheets; keep Blue accessible at the bottom right. No row separator lines.
- Support Dynamic Type, VoiceOver labels, 44-point touch targets, dark appearance and Reduce Motion. Keep navigation and drafts alive across locale changes. Use system materials only at navigation/input boundaries.
- No remote inference backend, telemetry, downloaded model weights, secrets, or user data in logs. User-requested web enrichment may send public topic titles to Wikipedia, never private notes; retain source links and distinguish fetched facts from personal fields. A DEBUG-only loopback Mac model bridge may support the simulator when Apple's simulator assets fail; label it clearly and exclude it from device/Release builds. Export is explicit and versioned. Keep performance datasets separate from normal user data.

## Commands and definition of done
Run from repository root; scripts select `/Applications/Xcode.app/Contents/Developer` without changing the system developer directory.
- Generate: `xcodegen generate`
- Formatting/localization: `scripts/check.sh`
- Simulator build: `scripts/build.sh Debug`
- Boot, install, launch: `scripts/run.sh`
- Unit and UI tests: `scripts/test.sh`
- Release verification: `scripts/build.sh Release`
- Unsigned iPhone SDK build: `scripts/build-device.sh` (signing and installation are done locally in Xcode).
- Genuine Mac model integration: `scripts/test-model-mac.sh` (production record tools/store; alarm actions unavailable in this harness).
- Genuine simulator chat: `scripts/start-model-bridge.sh`, then `scripts/test-bridge.sh` (explicit DEBUG loopback bridge to the Mac model).
- Performance: `scripts/profile.sh` (Release XCTest metrics; record actual results in `docs/verification.md`).
- Physical iPhone: `open Blue.xcodeproj`, choose your Personal Team and connected iPhone, then Run (⌘R). See `docs/release.md`. No paid distribution pipeline.
- Domain/data changes: meaningful Swift Testing coverage. UI changes: relevant XCTest flow plus inspect simulator screenshots at normal and compact sizes, both languages. Integration changes: test failure paths with doubles and report device checks separately. Every delivery must report limitations accurately.
- Before the first push: build, install, launch, test the exact-record edit/relaunch flow locally and inspect the running UI. Before delivery: repeat relevant checks and verify Release compilation. See [Xcode testing](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project).
- Account-dependent operations: public GitHub repository creation/push and free Personal Team signing in Xcode. No secrets in Git. Direct device setup follows [Apple's device-run guidance](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

Keep `docs/architecture.md`, `docs/design.md`, `docs/release.md`, and `docs/verification.md` aligned with the implementation. The verification report records the exact commands, measurements and remaining physical-device checks for the current delivery.
