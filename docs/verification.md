# Verification — 8 November 2026, clean navigation and semantic assistant

Public repository: `iOrb/blue-app`. Delivery includes the native simulator app and the private web preview. No TestFlight, App Store Connect, paid membership or distribution secrets are configured. Physical installation remains a free Personal Team action in Xcode.

## Environment and commands

macOS 26.6.2, Apple silicon; Xcode 27.2 (27B52), Swift 6.4.2, complete concurrency checking, minimum iOS 26.0. Tests ran on iOS 27.2 in the isolated Blue Verification (iPhone 17 Pro) and Blue Compact (iPhone 13 mini) simulators. The main Blue iPhone library was preserved.

- `xcodegen generate`
- `scripts/check.sh` — 213 localized keys, English/Spanish placeholders and formatting pass.
- `scripts/build.sh Debug` — followed by test builds after the final changes.
- `BLUE_DEVICE_NAME='Blue Verification' scripts/test.sh`
- `BLUE_DEVICE_NAME='Blue Compact' BLUE_DEVICE_TYPE='com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini' scripts/test.sh -only-testing:BlueUITests/BlueUITests`
- Targeted UI reruns after fixing the assistant's duplicated accessibility navigation and large-text layout.
- `scripts/test-model-mac.sh` — actual Foundation Models, shared production tools/store, isolated synthetic data.
- `BLUE_DEVICE_NAME='Blue Verification' scripts/profile.sh`
- Final `scripts/build.sh Release`, `scripts/build-device.sh` and `scripts/run.sh` pass. The latter installs/launches the updated Debug app on Blue iPhone without resetting its library.

## Native results

All 32 Swift Testing tests passed in `Tests-20261108-190217.xcresult`. They cover typed values, optimistic revisions, rollback, persistence/relaunch, legacy flattening, shared indicators, schema confirmation, calendar event persistence and stale deletion, read-only tool restrictions and AlarmKit adapter failure paths.

All seven regular UI flows passed across the full runs and focused corrections:

- `Tests-20261108-184212.xcresult`: six compact flows passed before the final chat-navigation/accessibility refinements.
- `Tests-20261108-190217.xcresult` (normal) and `Tests-20261108-190510.xcresult` (compact): six of seven UI flows passed; the chat test exposed a duplicate accessibility element for the background navigation. The hidden background navigation was then removed while the assistant sheet is open.
- `Tests-20261108-190753.xcresult`: corrected Enter/result/direct-navigation/draft-preservation chat flow passed on the compact simulator.
- `Tests-20261108-190957.xcresult`: final chat and overview/calendar-day flows passed after extending the sheet background through the bottom safe area.
- `Tests-20261108-191058.xcresult`: maximum accessibility text size passed in dark appearance after removing the redundant month header at that size. Simulator appearance was restored afterwards.

Screenshots were inspected at normal and compact widths in both languages, plus maximum text size/dark appearance. They show title-only note overviews, collection names/counts, shared visual properties, automatic saving after relaunch, rendered Markdown, calendar agenda sheets, and the Blue sheet without Close/Save/Edit/Undo buttons. Screenshot fixtures contain synthetic data. See [screenshots](screenshots).

## Real model verification

The final Mac integration run passed ten checks: named exact-record read from the overview, open-record rating read, implicit Spanish 8.5 edit with reopen verification, negated edit without mutation, shortening the second paragraph while preserving the heading/other paragraph/title, staging field removal, calendar creation without an alarm, moving the same event to 22:00, preparing its deletion for confirmation, and a French rating edit.

Observed request times in that run were 1.50–9.52 seconds. In the negated-edit case the model requested clarification and made no change. These checks establish the tested outcomes, not universal language understanding. Earlier runs exposed wrong note rewrites, field-removal arguments, and reference selection; the implementation now uses a semantic target resolver, focused block-edit instructions, explicit schema intent, readable ISO dates and retained event context. IDs, types, revisions, limits and the one-mutation ledger remain deterministic validation.

The production web Worker, authenticated gateway and rebuilt Mac bridge passed five additional genuine requests: named rating lookup (2.61 s), note block edit (2.57 s), calendar creation (3.36 s), follow-up move (4.26 s), and a custom 🗿 purple indicator with a 🚬 collection icon (4.71 s). Import markers and events survived round trips. Browser Enter-to-send displayed only Interstellar and its exact stored rating, inside the Blue sheet. The same read-only flow also succeeded on the deployed owner-private Site.

The web connection requires this Mac and its temporary tunnel to remain running. The native Release/device target contains no bridge. Native Apple Intelligence is unavailable on an iPhone 13 mini; manual features remain available there. The simulator bridge is explicitly identified as a DEBUG development path.

## Performance

`Performance-20261108-190521.xcresult` passed four Release UI metrics tests and the pure query benchmark. Three launch/scroll samples and ten query samples; setup excluded. Other verification work ran on the Mac concurrently, so these are development observations, not hardware guarantees or controlled before/after comparisons.

| Metric | 27 records | 10,000 records |
| --- | ---: | ---: |
| First responsive frame, mean | 3.106 s | 3.221 s |
| Scroll peak physical memory, mean | 86.64 MB | 109.12 MB |
| Swipe/deceleration interval, mean | 2.556 s | 2.583 s |
| Search + numeric sort, median | 0.054 ms | 50.867 ms |
| Search + numeric sort, maximum | 1.187 ms | 55.351 ms |

No numerical hitch result was emitted; no zero-hitch claim is made. Collection queries and persistence diffing are on the main actor; this is a bounded personal-library implementation, not a paginated database.

## Remaining checks and limits

- Free Personal Team signing, actual iPhone installation and physical Safari/Home Screen behavior remain unverified.
- Actual AlarmKit permission/delivery while locked, recurrence, Focus/silent behavior, revocation and time-zone changes require hardware. Calendar events do not ring.
- Microphone permission, interruption and recognition on the physical iPhone; VoiceOver speech/order and battery/thermal behavior remain device checks.
- AI output is probabilistic and can need clarification. Catalogs and note size are bounded; multi-part requests can require separate turns. Exact saved facts are rendered from the store rather than generated prose.
- Web storage is browser-local; the private one-time import preserves existing data but is not ongoing native/web synchronization. The published Site was opened in the available signed-in browser session and a real rating query succeeded.
- Xcode's diagnostic collector sometimes reports unavailable global `simctl`/debugger metadata because system xcode-select remains on Command Line Tools. Scripts explicitly select Xcode; build/test outcomes above are actual completed results.
