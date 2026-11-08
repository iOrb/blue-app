# Run Blue on your own iPhone

Blue uses your free Apple Account (Personal Team) for direct installation from Xcode. There is no TestFlight workflow, App Store Connect dependency, paid team requirement, or distribution secret. GitHub Actions only verifies the source. The public repository does not contain Apple credentials.

## First installation

1. Open `Blue.xcodeproj` in Xcode. In Xcode → Settings → Apple Accounts, sign in with your existing Apple Account.
2. With iOS 27 or later, pair without a cable: keep the unlocked iPhone and Mac on the same Wi-Fi, open Xcode → Open Developer Tool → Device Hub, then + → Pair Nearby Device… → iPhone. Keep that sheet open and return to Settings → Privacy & Security → Developer Mode on the iPhone; follow the pairing instructions on both devices. Enter any pairing code only where Apple requests it. For earlier iOS releases, connect a cable for the first pairing and accept Trust This Computer.
3. On the iPhone, enable Settings → Privacy & Security → Developer Mode and complete the required restart/confirmation. Do this yourself on the device.
4. Select the **Blue** project → **Blue** target → **Signing & Capabilities**. Keep **Automatically manage signing** enabled. Choose your name **(Personal Team)** from Team. Only the app target needs device signing for a normal Run.
5. The proposed bundle ID is `app.iorb.blue.ios`. If Xcode says it is unavailable, use a unique identifier such as `app.iorb.blue.personal.<your-suffix>`. Keep it stable after installation so future builds update the same app and preserve its data. Make the same change in `project.yml` before regenerating the project; account/team settings can stay local.
6. Select your physical iPhone as the run destination and press **⌘R**. Xcode registers the selected device, creates a development profile and installs Blue. If the Signing pane reports that your team has no devices, select the paired iPhone before running so Xcode can register it. If iOS asks to trust your developer identity, follow the device's Settings → General → VPN & Device Management prompt.

No `.p12`, `.p8`, App Store profile, App Store app record, API key or GitHub secret is needed. A simulator build does not need an Apple Account at all.

Free Personal Team provisioning is temporary. Apple states that App IDs, registered test devices and provisioning profiles expire after seven days; you may need to reconnect and run the app again from Xcode. Keep the bundle ID unchanged and do not delete Blue to refresh signing. Export a backup from Blue Settings before any reinstall that could remove app data.

iOS 27 enables wireless first pairing in Device Hub. On iPhone 13 mini, Blue opens local library search because the device lacks Apple Intelligence. Manual collections, notes and calendar work on that phone. See [Apple Intelligence requirements](https://support.apple.com/en-us/121115).

To bring a previously exported collection or note to this device, open Blue Settings and choose **Import collections and notes**. Choose a native Blue version 2 JSON export in Files. Existing collections and notes keep their local edits.

## Device checks

- Confirm English/Spanish switching while editing a note and with a Blue-applied collection query active. Check collection back/options, ascending/descending sorting, plain-text notes, centered deletion modal, Liquid Glass navigation, the composer immediately above the keyboard, outside-tap dismissal and preserved drafts at the physical keyboard size.
- Tap a rating, scroll the number picker, dismiss it, terminate Blue and confirm persistence. Create a calendar event through + and check the day sheet after relaunch.
- On an Apple Intelligence-compatible iPhone with its local model ready, enable Airplane Mode and ask Blue to read Interstellar's rating, then change it. Verify the actual row and relaunch. Also say hello with that item selected, propose a note rewrite without saving, then explicitly accept the proposal. Manual functionality works on iPhones without that model.
- Create an alarm a few minutes ahead, grant the AlarmKit permission, lock the phone, and verify delivery. Check silent/Focus modes, permission denial, disable/delete, recurrence and time-zone changes. Personal Team installation itself does not establish these behaviors.
- Review Dynamic Type, VoiceOver reading order, Reduce Motion and keyboard interactions on the real display.

On 8 November 2026, Blue 1.0 (build 1) was signed with a Personal Team, installed over Wi-Fi, and launched on a physical iPhone 13 mini running iOS 27.3. The first launch succeeded after the developer profile was trusted on the iPhone.

Sources: [iOS 27 wireless pairing in Device Hub](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac), [Apple account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account/), [running on devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [assigning a team](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html).
