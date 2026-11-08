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

The current delivery has 30 Swift Testing tests and ten regular XCTest UI flows. The final accessibility/chat/favorite-toggle checks passed in `artifacts/Tests-20261108-133412.xcresult`, followed by successful Release and unsigned iPhone SDK builds. The full run in `artifacts/Tests-20261108-130618.xcresult` passed all 40; the final 30-test data pass and rendered-note/maximum-text-size flows also passed in `artifacts/Tests-20261108-132104.xcresult`. Test artifacts are local and ignored by Git. Curated simulator screenshots are in [screenshots](screenshots), including [custom indicators](screenshots/custom-indicators.png). The compact flow was rerun after changing accessibility-sized property grids to one column and limiting action glyph sizes (`artifacts/Tests-20261108-132445.xcresult`); it confirmed Accessibility XXXL, dark appearance and Reduce Motion.

## Functional evidence

`scripts/check.sh` validates strict Swift formatting, shell/Python syntax, and 203 English/Spanish catalog keys with matching placeholders. Swift compiler diagnostics are checked separately from Xcode's test-bundle App Intents metadata notice.

The data tests cover typed values and queries, backward decoding, folder-to-collection migration without losing notes, durable edits and deletion, no reseeding, stale revisions, undo, JSON export, exact navigation through conflicting filters, ambiguity, mutation/cancellation authorization, numeric evidence including Spanish decimal commas, adaptive fields, custom icons, destructive schema review, and alarm scheduling/reconciliation failure paths. Existing field types remain authoritative when the model redundantly describes them during a value edit.

The ten regular UI flows cover:

- Assistant read → exact row → Spanish switch → edit → relaunch persistence.
- Unsaved Markdown and navigation across language changes.
- Combined collection filters and individual removal.
- Empty and custom collections, with no folder UI or creation templates.
- Calendar and a disabled alarm.
- Accessibility descriptions and 44-point hit regions.
- Configured Dynamic Type, keyboard and calendar layout.
- Enter-to-send, outside dismissal, retained chat draft, favorites and the microphone action.
- Custom 🗿/🚬 indicators in rows, details and icon filters.
- Saved notes opening in rendered Markdown and switching to manual editing.

These regular assistant flows explicitly use a deterministic test double. They do not prove model quality or speech recognition. The microphone action exists and the service requires on-device recognition, but physical audio capture still needs hardware verification.

## Genuine model checks

The Mac's Foundation Models service reports available. The Mac integration and simulator bridge compile the production store, routing and tools; the Mac-only alarm adapter rejects alarm actions. No scripted assistant is used in these checks. Catalog resources are generated alongside the standalone Mac executable so built-in labels resolve in both languages. The final `scripts/test-model-mac.sh` run passed English read/edit/reopen, Spanish read/decimal-comma edit/reopen, and a requested numeric-distance/choice-difficulty collection. The first useful read took 1.808 seconds; read plus persisted follow-up edit took 7.755 seconds. A model response error after a successful read did not discard the validated tool result. Explicit kind guidance corrected an earlier choice-field/checkbox mismatch.

The genuine model was exercised on synthetic data through the loopback helper:

| Request | Observed result |
| --- | --- |
| Save Lake Walk in Trails with distance 5 | One collection/item saved; no invented description or private-topic web lookup |
| Add a purple 🗿 Bass indicator and 🚬 collection icon | Exact emoji, label and color persisted |
| Remove a populated distance field | Revision-bound confirmation proposed; field and value retained until approval |
| Save Interstellar with public information | Wikipedia source titles, excerpts and links saved |
| Set its rating to Spanish `8,5` | Numeric 8.5 persisted |
| Add director and year from sources | Christopher Nolan and 2014 persisted; personal rating 8.5 retained |
| Create/edit a Markdown checklist note | Heading and checkbox markers persisted; a specifically requested second item was added while preserving the first |

The model can ask for clarification or miss an underspecified edit; a general checklist-add request required a more explicit follow-up in testing. No universal completion guarantee is implied. Individual synthetic requests took approximately 2–12 seconds on this Mac. These are observations, not latency guarantees. Wikipedia may return similarly named works; source links remain visible and users can review them. Factual filling is limited to evidence in returned excerpts, not arbitrary web research.

The opt-in `scripts/test-bridge.sh` passed in `artifacts/Tests-20261108-131941.xcresult`: the simulator chat read Interstellar, changed its rating to 9.5 and verified that value after terminating/relaunching. This uses the actual Mac model, with no deterministic assistant. The final complete UI flow took 37.4 seconds, including typing, navigation, startup and relaunch. The ordinary simulator model test remains separate: Apple's simulator reports availability but generation fails with UnifiedAssetFramework error 5000 while loading its model catalog. The explicit DEBUG bridge works around that development-runtime limitation. It is compiled out of iPhone and Release builds. A compatible iPhone with Apple Intelligence ready must still pass its own offline check.

```sh
scripts/test-model-mac.sh
scripts/start-model-bridge.sh
scripts/test-bridge.sh
# Separate test of Apple's simulator model, when its assets work:
BLUE_REAL_MODEL_TESTS=1 scripts/test.sh -only-testing:BlueTests/RealModelTests
```

## Performance method

`scripts/profile.sh` uses optimized Release code, testability enabled only for the measurement build, coverage disabled, and isolated simulator data. The `PERFORMANCE_PROBE` compile flag enables dataset setup, not a fake assistant. It measures 27 seeded records and 10,000 records. Launch and scrolling use three samples; the pure search-and-sort query uses ten. Setup is excluded from measurement. Launch means a new app process against a prepared store, with simulator/OS caches potentially warm; it is not physical-device cold boot.

The Release run `artifacts/Performance-20261108-133043.xcresult` passed all four UI performance tests and the pure query benchmark after the collection/assistant changes. It precedes only the final library favorite-star styling; no query, persistence, or collection-row code changed afterwards.

| Metric | 27 records | 10,000 records |
| --- | ---: | ---: |
| XCTest first responsive frame, mean | 2.890 s | 3.198 s |
| Scrolling peak physical memory, mean (decimal MB) | 89.26 MB | 128.25 MB |
| Swipe/deceleration interval, mean | 2.557 s | 2.556 s |
| Search + numeric sort, median | 0.057 ms | 50.003 ms |
| Search + numeric sort, maximum | 0.081 ms | 55.197 ms |

These results remain within the investigation budgets below. Earlier UI versions measured 5.966/6.315-second responsiveness and 0.115/93.910-ms query medians on this Mac. Changed layouts, simulator state and caches prevent attributing that difference to a single optimization. `XCTHitchMetric` was requested but emitted no numerical hitch samples; no zero-hitch claim is made.

XCTest launch values include the test environment's responsiveness instrumentation. They must not be presented as an iPhone launch guarantee. A swipe interval is not a hitch count.

Initial investigation budgets on this same Mac/runtime: normal query p50 below 1 ms; 10,000-record query p50 below 150 ms; scrolling peak memory below 120/230 MB; launch responsive-frame average below 7/9 s. Investigate repeated regressions above 20% on the same configuration. Establish separate physical-device budgets after measurement. These are engineering thresholds, not hard-coded assertions on shared CI hardware.

## Simulator diagnostic limits

Xcode 27.2 intermittently reports a SwiftUI “Invalid frame dimension” runtime warning during the assistant keyboard transition. No negative or non-finite dimensions are supplied by Blue, and the tested keyboard, navigation and save flows complete, but the SDK warning remains open for investigation. Xcode's optional diagnostic collector also invokes `simctl` through the Mac's global Command Line Tools selection and reports it missing; the build/test/run scripts explicitly select Xcode and complete successfully. The global developer directory was left unchanged.

## Remaining device checks

- Personal Team signing and direct iPhone installation: no iPhone was connected during this task.
- Real production assistant read/edit in Airplane Mode, ambiguity and tool-generated custom collection quality.
- AlarmKit permission UI, actual sound while locked, silent/Focus behavior, recurrence, revocation, and time-zone changes on hardware. Tests of the adapter's failure paths do not prove OS delivery.
- On-device microphone dictation, permission denial, interruption and stop behavior.
- VoiceOver reading order and speech, keyboard ergonomics, and sustained battery/thermal performance.

No alarm delivery or on-device model success is inferred from a fake scheduler or deterministic UI assistant. See [architecture](architecture.md) for persistence and scaling tradeoffs and [the workflow](../.github/workflows/checks.yml) for reproducible CI. CI uses the published `xcode-27` macOS runner with Xcode 27.1 and iOS 27.0, explicitly checked before testing; local results use the configuration above.

## Follow-up: collection controls and CI portability (2026-11-08)

The first complete GitHub run (`42481055755`) exposed inaccessible collection controls after assistant scrolling and a UI test that tried to tap the tab bar while the software keyboard covered it. Collection controls now occupy a separate stack above the list, keeping their hit regions outside the scrolling surface. The UI test uses a visible favorite-filter control to verify that one outside tap both acts and dismisses chat; it does not tap the navigation title, which can focus the system search field.

Local verification of the changed layout passed the exact-record edit/language/relaunch flow, filter persistence, and accessibility audit (`Tests-20261108-141010.xcresult`; its fourth test still had the navigation-title issue). After correcting that test, the chat/Enter/outside-tap/favorites flow passed in `Tests-20261108-141540.xcresult`. Release and unsigned iPhone SDK builds also passed. These checks used the separate `Blue Verification` simulator. The main simulator library was restored from its existing backup after an initially misdirected test launch was stopped.

The native CI workflow ignores web-only source and preview-documentation changes; native and shared changes still run its complete suite. The Safari preview has separate verification described in `docs/web-preview.md`.
