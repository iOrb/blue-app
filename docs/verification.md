# Local verification — 8 November 2026

The delivery is a public `iOrb/blue-app` repository, a running iPhone simulator app, and a project ready for local Personal Team signing. No distribution credentials, paid membership, App Store Connect record or TestFlight workflow is configured. Direct installation needs the user's connected iPhone and free Apple Account in Xcode; see [device setup](release.md).

## Configuration

- macOS 26.6.2 (25G83), Apple silicon.
- Xcode 27.2 (27B52), Swift 6.4.2, Swift 6 language mode with complete concurrency checks.
- iOS deployment target 26.0. Local simulator runtime iOS 27.2 (24B8117).
- Main simulator: iPhone 17 Pro, 402-point width, named Blue iPhone.
- Compact simulator: iPhone 13 mini, 375-point width, named Blue Compact.
- XcodeGen 2.46.0 generates the checked-in project from `project.yml`.
- No runtime third-party dependencies. Simulator builds have signing disabled.

## Verified commands

- `xcodegen generate`
- `scripts/check.sh`
- `scripts/build.sh Debug` and `scripts/build.sh Release`
- `scripts/run.sh` (install and launch in Device Hub)
- `scripts/test.sh`, plus targeted re-runs after fixes and compact-device runs using `BLUE_DEVICE_NAME='Blue Compact' BLUE_DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini`
- `scripts/profile.sh`
- `scripts/test-model-mac.sh`
- `scripts/build-device.sh` — unsigned `iphoneos` SDK compilation passes; this does not establish Personal Team signing or installation.

The last local unit/compact pass contains all 26 unit tests and the final maximum-text-size flow. All seven normal UI flows passed across the full run and targeted corrections. Screenshots from the running simulator are in [screenshots](screenshots), including [compact collection](screenshots/compact-collection-en.png) and [accessible calendar](screenshots/compact-calendar-es.png).

## Functional evidence

`scripts/check.sh` passes: strict swift-format lint, shell/Python syntax, and 174 catalog keys with English/Spanish translations and matching placeholders. Explicitly identical translations are allowlisted. There are no Swift compiler warnings in the final source; Xcode may emit a test-bundle App Intents metadata-extraction notice because that bundle exposes no intents.

26 Swift Testing tests pass, covering typed values, numeric sorting with missing values, combined filters, folder depth, schema validation, starter semantics, durable edits and deletion, no reseeding of empty data, stale-edit rejection, undo, JSON export, exact navigation with conflicting filters, ambiguous tool reads, mutation/cancellation rules, read-only request authorization, collection query validation, model error mapping, request replacement, property migration, alarm permission denial and scheduling failure, system cancellation reconciliation, recurrence and time-zone changes.

XCTest exercises assistant read → exact row → Spanish switch → edit → save → relaunch; unsaved Markdown with a language switch; multiple filters and individual removal; simple and custom collections; calendar and a disabled alarm; accessibility audits; and keyboard/layout behavior at the configured text size. Deterministic assistant flows are explicitly test doubles, not real-model evidence.

All seven XCTest flows were exercised at normal text size. The compact pass uses the maximum Accessibility XXXL size, dark appearance and Reduce Motion enabled; the test runner confirmed `UICTContentSizeCategoryAccessibilityXXXL` and `reduceMotion=true`. At accessibility sizes, numeric field editors stack their label/value, the calendar uses a native date picker, and filters open at full height. This avoids crowding a month grid or narrow property row.

The automated accessibility audit checks sufficient descriptions and hit regions in the library, collection and calendar. It initially caught small calendar targets; explicit content shapes and minimum 44-point targets corrected them. Manual VoiceOver listening on a physical device remains a separate check.

## Real model

The Mac's genuine Foundation Models service reported available. `scripts/test-model-mac.sh` compiles the production domain, SwiftData store, localization, assistant orchestration and tools against the Mac SDK. Only AlarmKit is replaced with an adapter that rejects alarm actions. The harness creates a fresh temporary database and verifies actual model read → follow-up edit → reopen, using the same code as the iPhone app. This is not the deterministic assistant.

The initial real-model run chose an unrelated tool when all seven tools were exposed together. The assistant now uses a typed, on-device intent classification and exposes only the one or two tools relevant to records, collections, notes or alarms. The subsequent real read/edit/reopen test passed. Read requests now have mutation authorization disabled; the model receives only read tools. Collection field kinds and templates are constrained enums, preventing unsupported generated type names. With the final constrained tool schemas, the first useful English result took 3.344 s, and read plus persisted follow-up edit took 7.839 s in that run. The same harness also passed a Spanish read and decimal-comma edit to 8.5, followed by reopening the store. A real-model hiking collection was created and validated with numeric and status fields and bilingual labels. This is a single Mac measurement, not an iPhone latency guarantee.

The opt-in iOS integration test was also attempted with the production record tools. Although the simulator reported model availability, generation failed with `com.apple.UnifiedAssetFramework` error 5000 while loading its model catalog. This is **not** a passed real-model iOS test. Blue maps that runtime failure to a localized model-not-ready message; manual editing remains available. Confirm the full production model flow offline on a compatible iPhone with Apple Intelligence ready.

```sh
scripts/test-model-mac.sh
BLUE_REAL_MODEL_TESTS=1 scripts/test.sh -only-testing:BlueTests/RealModelTests
```

The smaller `scripts/model-smoke.swift` fixture is retained for separating system-model availability from the production tool integration.

## Performance method

`scripts/profile.sh` uses optimized Release code, testability enabled only for the measurement build, coverage disabled, and isolated simulator data. The `PERFORMANCE_PROBE` compile flag enables dataset setup, not a fake assistant. It measures 27 seeded records and 10,000 records. Launch and scrolling use three samples; the pure search-and-sort query uses ten. Setup is excluded from measurement. Launch means a new app process against a prepared store, with simulator/OS caches potentially warm; it is not physical-device cold boot.

The first baseline, before moving large collection queries to a cancellable background task, measured:

| Metric | 27 records | 10,000 records |
| --- | ---: | ---: |
| XCTest first responsive frame, mean | 5.804 s | 6.908 s |
| Scrolling peak physical memory, mean | 85.42 MB | 173.00 MB |
| Swipe/deceleration interval, mean | 1.089 s | 2.562 s |
| Search + numeric sort, median | 0.144 ms | 93.473 ms |
| Search + numeric sort, maximum | 0.152 ms | 97.076 ms |

The final Release run after the query/background and accessibility changes passed all four UI performance tests plus the query benchmark:

| Metric | 27 records | 10,000 records |
| --- | ---: | ---: |
| XCTest first responsive frame, mean | 5.966 s | 6.315 s |
| Scrolling peak physical memory, mean | 85.34 MB | 183.32 MB |
| Swipe/deceleration interval, mean | 1.101 s | 2.573 s |
| Search + numeric sort, median | 0.115 ms | 93.910 ms |
| Search + numeric sort, maximum | 1.942 ms | 96.594 ms |

The query change moves work away from the main actor; it does not claim a faster sorting algorithm. Stress peak memory increased by about 6% while retaining the cached result snapshot. Results are within the initial investigation budgets below. `XCTHitchMetric` was requested but emitted no hitch samples in either the log or the exported xcresult metrics on this simulator. A numerical hitch baseline remains pending hardware; no zero-hitch claim is made.

XCTest launch values include the test environment's responsiveness instrumentation. They must not be presented as an iPhone launch guarantee. A swipe interval is not a hitch count.

Initial investigation budgets on this same Mac/runtime: normal query p50 below 1 ms; 10,000-record query p50 below 150 ms; scrolling peak memory below 120/230 MB; launch responsive-frame average below 7/9 s. Investigate repeated regressions above 20% on the same configuration. Establish separate physical-device budgets after measurement. These are engineering thresholds, not hard-coded assertions on shared CI hardware.

## Simulator diagnostic limits

Xcode 27.2 intermittently reports a SwiftUI “Invalid frame dimension” runtime warning during the assistant keyboard transition. No negative or non-finite dimensions are supplied by Blue, and the tested keyboard, navigation and save flows complete, but the SDK warning remains open for investigation. Xcode's optional diagnostic collector also invokes `simctl` through the Mac's global Command Line Tools selection and reports it missing; the build/test/run scripts explicitly select Xcode and complete successfully. The global developer directory was left unchanged.

## Remaining device checks

- Personal Team signing and direct iPhone installation: no iPhone was connected during this task.
- Real production assistant read/edit in Airplane Mode, ambiguity and tool-generated custom collection quality.
- AlarmKit permission UI, actual sound while locked, silent/Focus behavior, recurrence, revocation, and time-zone changes on hardware. Tests of the adapter's failure paths do not prove OS delivery.
- VoiceOver reading order and speech, keyboard ergonomics, and sustained battery/thermal performance.

No alarm delivery or on-device model success is inferred from a fake scheduler or deterministic UI assistant. See [architecture](architecture.md) for persistence and scaling tradeoffs and [the workflow](../.github/workflows/checks.yml) for reproducible CI. CI uses the published `xcode-27` macOS runner with Xcode 27.1 and iOS 27.0, explicitly checked before testing; local results use the configuration above.
