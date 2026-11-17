# Blue internal TestFlight delivery

Current plan (17 November 2026): paid Apple Developer Program, internal TestFlight and Xcode Cloud. No public App Store release is authorized. Keep bundle ID `app.iorb.blue.ios` and the existing team `Z33UY64QQA`; never uninstall the existing app to change delivery. Xcode shows the account as Admin on a developer team, but its Cloud team chooser currently offers no eligible team. Paid membership activation and App Store Connect access still need verification.

## Delivery workflow

1. Complete local checks (`scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh Release`, `scripts/build-device.sh`) before uploading a build.
2. Preserve a verified device backup before the first development-to-TestFlight replacement. A matching bundle ID alone is not a guarantee that signing/access groups and all data survive; compare the old and new application identifiers and keychain entitlements. Never delete the existing app as a workaround. Drive backup permission, upload/readback and recovery must be verified separately.
3. Create or reuse the App Store Connect iOS app for the exact bundle ID. Use English as the primary language and a stable internal SKU (`blue-ios`). The visible app name may need an available variation if Blue is already taken.
4. In Xcode → Product → Xcode Cloud → Create Workflow, connect only `iOrb/blue-app`. Use the shared BlueCloud scheme (unit tests exclude live-provider and performance suites) and a cloud Xcode version compatible with the local toolchain. `ci_scripts/ci_post_clone.sh` verifies localization, formatting and shell syntax without installing dependencies. The committed project is generated locally from `project.yml`. GitHub Actions runs lightweight localization and shell checks on a hosted Linux runner; the old unavailable `xcode-27` runner is removed.
5. Configure a main-branch trigger with cancellation of superseded runs, simulator unit tests, Release archive for iOS and internal TestFlight distribution after success. Exclude real-provider/bridge and performance suites from routine cloud tests; these require separate opt-in runs. Start cloud build numbering above all existing uploaded builds (initial proposal: 100). Let Xcode Cloud manage subsequent build numbers and signing.
6. Create an internal testing group, add the existing Apple Account, and enable automatic distribution. Install Apple's TestFlight app on the iPhone, accept the invitation, and enable automatic updates there. New builds still need Apple processing; availability and automatic installation are not instantaneous. TestFlight builds expire after 90 days.
7. Verify library data, provider credentials, Google connection, voice and real alarms after the first replacement. Test voice on the physical iPhone, outside iPhone Mirroring. TestFlight feedback and Apple crash reports support diagnosis without adding a third-party telemetry SDK; never include private library contents or keys in diagnostics.

Use only the included Xcode Cloud allowance (25 compute hours/month). Do not purchase extra capacity. Repository access grants and any pending legal agreement need the account holder's approval. No App Store Connect API key, `.p8`, `.p12` or GitHub distribution secret is required for Apple-managed Xcode Cloud signing.

## Local fallback

`scripts/archive.sh` creates a signed Release archive without uploading it. Open it in Xcode Organizer to validate and distribute to App Store Connect. `scripts/update-iphone.sh` remains a local development fallback; it is not necessary for TestFlight updates. Simulator work does not require signing.

## Cloud backup scope

Existing optional Google Drive backup stays independent of TestFlight. It writes one encrypted snapshot per installation, with readback verification and a separate account-protected recovery key; see [backup format](backup-format.md). It is not continuous multi-device synchronization. iCloud automatic backup is not enabled yet: it requires its own container, a recoverable encryption-key lifecycle, restore UI, conflict rules and round-trip tests before activation. Paid membership alone does not implement or verify these behaviors. Do not replace a working backup with an empty or unreadable state.

## Current activation status

Local preparation is in progress. No successful TestFlight upload, Xcode Cloud workflow or iCloud container is claimed until verified in the relevant Apple service. App Store privacy/export declarations and any agreements must reflect the actual app and account before distribution.

Sources: [Xcode Cloud setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [TestFlight distribution](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight), [included cloud allowance](https://developer.apple.com/xcode-cloud/get-started/).

## Device verification after installation

- Confirm notes, collections, covers and events survive the first replacement and a relaunch.
- Check saved BYOK credentials and Google sign-in; reauthorize only if needed. Do not assume Keychain access survives a changed signing prefix.
- Open voice on the physical phone outside iPhone Mirroring; verify microphone input and spoken replies.
- Create a future event, then change its name/time/repeat. Verify AlarmKit plus notification delivery with the phone locked; permissions remain device-owned.
- Verify the optional Drive copy by downloading, decrypting and comparing the saved snapshot. A signed-in account alone does not prove upload or recovery.
- Exercise English/Spanish, text editing, compact display, Dynamic Type and VoiceOver.

## App Store preparation, without publication

Keep the privacy manifest, permission descriptions, app icon and encryption declaration consistent with the actual build. Before any later public release, complete App Store privacy answers, provider-data disclosures, support/privacy URLs, screenshots, review notes and account-specific export compliance. The app currently has no Blue inference server or third-party analytics SDK. BYOK requests and optional Google backups have their own data destinations. No public-release submission is part of this delivery.
