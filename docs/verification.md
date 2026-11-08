# Verification — 8 November 2026, compact collections and plain notes

Public repository: `iOrb/blue-app`. Native simulator development and direct free Personal Team installation remain the delivery route; no paid distribution or TestFlight. Web version 5 is published owner-private at https://blue-iorb-mobile-20261108.ablazecloak.chatgpt.site using source `9001c6f46001936ab4338940f12dc36c35d2da31`, deployment `appgdep_6af0d325a9dc8191b33138804663eb2e`, environment revision 2.

## Environment and completed checks

macOS 26.6.2, Apple silicon, Xcode 27.2 (27B52), Swift 6.4.2; Swift 6 complete concurrency checks and minimum iOS 26.0. Isolated Blue Compact (iPhone 13 mini) and Blue Verification (iPhone 17 Pro) use iOS 27.2. The main Blue iPhone library is preserved.

- `scripts/check.sh`: formatting, 217 English/Spanish string keys, matching placeholders and script syntax pass.
- `BLUE_DEVICE_NAME='Blue Compact' BLUE_DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini scripts/test.sh`: six UI flows passed; the Spanish check exposed a 36-point system-toolbar menu and a dismissal timing assertion (`Tests-20261108-204726.xcresult`). The collection header now uses explicit 44-point controls and the test waits for presentation dismissal.
- Final focused compact command adds `-only-testing:BlueUITests/BlueUITests/testSpanishOverviewAndTouchTargets -only-testing:BlueUITests/BlueUITests/testNoteTapEditAutosaveAndRelaunch -only-testing:BlueUITests/BlueUITests/testCollectionSortIconsNumberWheelAndRelaunch -only-testing:BlueTests`. All 34 unit tests and all three UI flows pass in `Tests-20261108-205152.xcresult`.
- The note flow verifies plain-text line breaks after relaunch, cancel-with-cross, opening Blue from the detail, explicit confirmed deletion and absence after another relaunch. The collection flow verifies ascending/descending order, no manual filter bar/section navbar, a numeric wheel edit and persisted exact value. Spanish checks the 44-point fixed options header and top Blue composer.
- `scripts/build.sh Release`, `scripts/build-device.sh` and `scripts/run.sh` pass. The last command installs/launches Debug on the main Blue iPhone simulator without resetting its library; unsigned device compilation is not physical installation.
- Web `npm run typecheck`, `npm test` (nine tests) and the production build pass. The Sites workflow rebuilt the pushed source and packaged it; source/archive scans found no runtime token or private import payload.

All seven normal-size UI flows pass in `Tests-20261108-205436.xcresult` using `BLUE_DEVICE_NAME='Blue Verification' scripts/test.sh -only-testing:BlueUITests/BlueUITests`. This includes maximum accessibility text size/dark appearance, overview/calendar, chat Enter/result/draft preservation, collection sorting/number picker/relaunch, event autosave/delete cancellation, plain-note lifecycle and Spanish touch targets. Native UI tests use the explicitly identified DEBUG assistant double; they do not establish real model correctness.

After the final collection-title synchronization fix, the collection sorting/number-picker/relaunch flow was rerun (`Tests-20261108-210834.xcresult`, one UI test passed), followed by Release and unsigned iPhone SDK compilation. The open collection now observes store-driven title changes; the rerun checks the surrounding collection flow, not real-model renaming.

GitHub Actions [run 42517925858](https://github.com/iOrb/blue-app/actions/runs/42517925858) passed for public redesign commit `2f5e32478a53dbb562ad42472476ecd39d791ea6`: formatting/localization, compilation/tests, Release and unsigned iPhone SDK compilation. The small title-observer follow-up was verified locally as described above.

## Visual inspection

Compact native screenshots were inspected in both English and Spanish: centered collection title/count, left sort row, fixed back/options, filled eye indicators, centered detail properties and plain notes. Web inspection at 375 × 812 and desktop width verifies the same hierarchy, fixed controls during scroll, a floating Blue button within item details, a top chat composer, hidden section navigation and a centered delete modal with a top-right cross. Cancelling the web modal preserves the item. The published authenticated Spanish page retains existing lists, favorites and custom emoji indicators. Public screenshot fixtures in `docs/screenshots` contain test data; live user screenshots remain ignored under `artifacts`.

## AI verification and current blocker

An earlier candidate passed nine genuine Foundation Models conversation cases (`artifacts/conversation-model.log`, 1.18–8.21 seconds): greeting with a movie selected, capabilities, exact saved read after chat, thanks, a proposed note rewrite without saving, acceptance of the exact stored proposal, rename preserving the body, greeting plus new-note command, and English acknowledgement. Subsequent regression checks found that a boolean conversation classifier could misroute a saved-value question. The final semantic enum classifier passed an isolated twelve-message probe, including Spanish reads, field removal, proposals and implicit ratings; no command regex or keyword routing was introduced.

The final complete real-model rerun is **not passed**. During the regression run the Mac's own Foundation Models service began rejecting generation with `SensitiveContentAnalysisML` code 15 / underlying `ModelManagerError` 1013, despite reporting available. A separate minimal model probe then failed identically; rebuilding/restarting Blue's bridge did not fix the platform error. The final code surfaces `assistant.unavailable`. Earlier ten-case semantic and five-case web successes belong to the previous delivery, not proof of this final model revision.

Current production Worker HTTP checks pass four negative cases: unauthenticated (401), foreign origin (403), malformed request (400), oversized conversation history (400). A valid request through Worker → gateway → rebuilt bridge returns model-unavailable with the exact synthetic library unchanged and bounded conversation history. The six-case web conversational success suite remains blocked at the greeting by that same platform failure. Tokens and environment secrets were preserved. Actual native inference is unavailable on iPhone 13 mini; manual editing works there. The web testing path requires the Mac and tunnel to remain awake/reachable.

## Earlier performance baseline (before this redesign)

`Performance-20261108-190521.xcresult` passed four Release UI metrics tests and the pure query benchmark. Three launch/scroll samples and ten query samples; setup excluded. Other verification work ran on the Mac concurrently, so these are development observations, not hardware guarantees or controlled before/after comparisons.

| Metric | 27 records | 10,000 records |
| --- | ---: | ---: |
| First responsive frame, mean | 3.106 s | 3.221 s |
| Scroll peak physical memory, mean | 86.64 MB | 109.12 MB |
| Swipe/deceleration interval, mean | 2.556 s | 2.583 s |
| Search + numeric sort, median | 0.054 ms | 50.867 ms |
| Search + numeric sort, maximum | 1.187 ms | 55.351 ms |

No numerical hitch result was emitted; no zero-hitch claim is made. Collection queries and persistence diffing are on the main actor; this is a bounded personal-library implementation, not a paginated database.

## Physical installation

On 8 November 2026, Blue commit `5e7a8fd` was installed on an iPhone 13 mini running iOS 27.3, paired over Wi-Fi with Developer Mode enabled. The local signing team selection stays in the Mac's working copy. These commands omit the phone's name:

- `xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Debug -destination 'platform=iOS,name=<device-name>' -destination-timeout 15 -derivedDataPath .build-device -allowProvisioningUpdates -allowProvisioningDeviceRegistration build` registered the phone and built a signed app. `codesign --verify --strict --deep .build-device/Build/Products/Debug-iphoneos/Blue.app` passed.
- `xcrun devicectl device install app --device '<device-name>' --timeout 45 .build-device/Build/Products/Debug-iphoneos/Blue.app` succeeded. `xcrun devicectl device info apps --device '<device-name>' --bundle-id app.iorb.blue.ios --timeout 12` confirmed version 1.0, build 1.
- iOS initially rejected launch until the developer profile was trusted. `xcrun devicectl device process launch --device '<device-name>' --timeout 12 app.iorb.blue.ios` then succeeded, and `xcrun devicectl device info processes --device '<device-name>' --search 'Blue.app/Blue' --timeout 10` confirmed the app was running.

## Remaining physical and integration checks

- Recover the Mac's Apple model service, then rerun `scripts/test-model-mac.sh`, `scripts/test-model-mac.sh scripts/conversation-integration-mac.swift`, and genuine web conversation checks. No account or distribution credentials are required for this blocker. No universal language-understanding claim is made; pending proposals and new semantic classifier still require that final integration regression.
- iPhone Safari/Home Screen, microphone permission/interruption and VoiceOver reading order remain unverified on hardware.
- Actual AlarmKit authorization/delivery, recurrence, Focus/silent behavior, revocation and time-zone changes require an iPhone. Calendar events do not ring.
- Browser storage is local to that browser; the private one-time import is not continuous native/web synchronization. No offline service worker.
- Xcode's optional diagnostics collector may report missing global simctl/debugger metadata because xcode-select stays on Command Line Tools. The scripts explicitly select Xcode; completed build/test results are reported separately from these diagnostics.
