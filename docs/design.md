# Design decisions

Reviewed on 2026-11-08 before implementing collection controls:

- [Apple lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): use short text rows and reveal complete information in a dedicated editor. Preserve readable widths instead of compressing properties into desktop columns.
- [Apple Notes](https://support.apple.com/en-us/118442): adopt the recognizable folder/disclosure hierarchy, native search, and direct creation. Blue starts with six expanded folders; the collection title is not repeated when it matches the folder.
- [Craft](https://www.craft.do/): use restrained typography, content as the primary surface, and structured collections within a notes product. Avoid its broader workspace/task vocabulary for this release.
- [ThatPet](https://thatpet.app/): the useful principle is distinct reactions for listening, thinking, searching, working and completion. Blue's original character is drawn with SwiftUI paths and uses different eyes, arm poses and a search gesture; it does not reuse ThatPet artwork.
- [Apple Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub): Xcode 27 replaces the older standalone Simulator UI with Device Hub. The simulator runtime and simctl still provide reproducible build/test/install commands.

White/black system surfaces, secondary gray, and system typography handle both appearances. Blue is reserved for the character. Use system Liquid Glass for native navigation and restrained material for the assistant dock. Editors are pushed screens; only filters, property configuration and Settings need modal context. A modal has one close control.

Status filters use choices, ratings use a minimum slider plus optional maximum, numeric fields use numeric bounds, booleans use toggles, dates use a native date picker, and text/tags use matching text. The collection shows active removable chips with their current values, plus overflow removal and Clear All. Settings is near the start of the collection options menu so the navigation title and two primary controls fit on compact phones. Sorting is independent of filters. Hearts mean Like, stars mean Favorite, and a number means Rating. Optional values stay absent until populated.

At accessibility text sizes, number labels and values stack vertically, filter sheets use full height, and a native date picker replaces the crowded month grid. Accessibility requirements are enforced in AGENTS.md. Simulator screenshots and UI tests are recorded in `docs/verification.md`; a VoiceOver listening pass and real-device interaction remain distinct from automated accessibility audits.
