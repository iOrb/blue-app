# Blue internal TestFlight delivery

Current plan (17 November 2026): paid Apple Developer Program, internal TestFlight and Xcode Cloud. No public App Store release is authorized. Keep bundle ID `app.iorb.blue.ios` and the existing team `Z33UY64QQA`; never uninstall the existing app to change delivery. Membership and App Store Connect access are verified. The paid individual membership uses the same team ID as the previous development build. The Apple app record is **Blue by iOrb**, ID **6835902525** (the display name on iPhone remains Blue). The internal **Blue Internal** group has the account holder as its tester, with automatic distribution enabled for ordinary Xcode uploads. Cloud-distributed builds need the workflow post-action configured separately.

## Delivery workflow

1. Complete local checks (`scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh Release`, `scripts/build-device.sh`) before uploading a build.
2. Preserve a verified device backup before the first development-to-TestFlight replacement. A matching bundle ID alone is not a guarantee that signing/access groups and all data survive; compare the old and new application identifiers and keychain entitlements. Never delete the existing app as a workaround. Drive backup permission, upload/readback and recovery must be verified separately.
3. Create or reuse the App Store Connect iOS app for the exact bundle ID. Use English as the primary language and a stable internal SKU (`blue-ios`). The visible app name may need an available variation if Blue is already taken.
4. In Xcode → Product → Xcode Cloud → Create Workflow, connect only `iOrb/blue-app`. Use the shared BlueCloud scheme (Cloud test configuration excludes live-provider and performance suites at compilation) and a cloud Xcode version compatible with the local toolchain. `ci_scripts/ci_post_clone.sh` verifies localization, formatting and shell syntax without installing dependencies. The committed project is generated locally from `project.yml`. GitHub Actions runs lightweight localization and shell checks on a hosted Linux runner; the old unavailable `xcode-27` runner is removed.
5. Configure a main-branch trigger with cancellation of superseded runs, simulator unit tests, Release archive for iOS and internal TestFlight distribution after success. Exclude real-provider/bridge and performance suites from routine cloud tests; these require separate opt-in runs. Start cloud build numbering above all existing uploaded builds (initial proposal: 100). Let Xcode Cloud manage subsequent build numbers and signing.
6. Create an internal testing group, add the existing Apple Account, and enable automatic distribution. Install Apple's TestFlight app on the iPhone, accept the invitation, and enable automatic updates there. New builds still need Apple processing; availability and automatic installation are not instantaneous. TestFlight builds expire after 90 days.
7. Verify library data, provider credentials, Google connection, voice and real alarms after the first replacement. Test voice on the physical iPhone, outside iPhone Mirroring. TestFlight feedback and Apple crash reports support diagnosis without adding a third-party telemetry SDK; never include private library contents or keys in diagnostics.

Use only the included Xcode Cloud allowance (25 compute hours/month). Do not purchase extra capacity. Repository access grants and any pending legal agreement need the account holder's approval. No App Store Connect API key, `.p8`, `.p12` or GitHub distribution secret is required for Apple-managed Xcode Cloud signing.

## Local fallback

`scripts/archive.sh` creates a signed Release archive without uploading it. `scripts/upload-testflight.sh <archive>` uploads that verified archive using the existing Xcode account and automatic signing. Export options enforce internal TestFlight only and upload symbols for Apple crash diagnostics. Build numbers must be unique; increase the project version before each subsequent local archive. Xcode Organizer remains an alternative. `scripts/update-iphone.sh` remains a local development fallback; it is not necessary for TestFlight updates. Simulator work does not require signing.

## Cloud backup scope

Existing optional Google Drive backup stays independent of TestFlight. It writes one encrypted snapshot per installation, with readback verification and a separate account-protected recovery key; see [backup format](backup-format.md). It is not continuous multi-device synchronization. iCloud automatic backup is not enabled yet: it requires its own container, a recoverable encryption-key lifecycle, restore UI, conflict rules and round-trip tests before activation. Paid membership alone does not implement or verify these behaviors. Do not replace a working backup with an empty or unreadable state.

## Current activation status

Blue 1.0.0 (4) was uploaded on 19 November 2026. App Store Connect shows Testing in Blue Internal. This build adds the cover gallery and collection improvements. The source is available on the `mejoras-de-blue` branch.

The app record and internal tester group are created. The account holder renewed the Xcode session on 18 November 2026. Build 1.0.0 (3), including the new icon, was uploaded successfully using `scripts/upload-testflight.sh artifacts/Blue-20261118-142707.xcarchive`; Apple accepted the upload. App Store Connect now shows build 3 as **Testing**, assigned to **Blue Internal**, with **1 invitation** and 90 days of availability. The new icon appears on the build row. On 19 November the user confirmed successful installation, and App Store Connect showed Installed 1.0.0 (3) on iPhone 13 mini / iOS 27.3. Full library/credential continuity, voice and alarms still require separate checks. Xcode Cloud now recognizes the team and has reached Connect Source Code Repository; GitHub access and the actual workflow are not yet configured. The Apple web session is working; the remaining Cloud setup step needs GitHub sign-in and authorization in Chrome. No completed cloud workflow or iCloud container is claimed. App Store privacy/export declarations and any agreements must reflect the actual app and account before distribution.

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

## Home-screen icon update

Build 3 contains the new mascot icon. Info.plist resolves marketing/build versions from project settings so each new archive can be distinguished by Apple. Source artwork prompt is in app-icon.md. Once the first internal build is processed and available to the account holder, install TestFlight on the iPhone, accept its invitation, and turn on Automatic Updates in Blue's TestFlight page. TestFlight does not require a local network connection to the development Mac; it requires internet access. Automatic installation is controlled by iOS and is not guaranteed to occur immediately after a push. GitHub pushes alone do not upload an app until the cloud workflow is enabled.
