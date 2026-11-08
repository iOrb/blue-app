# Design decisions

Current design, reviewed on 2026-11-08:

- [Apple lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): use short text rows and reveal complete information in a dedicated editor. Preserve readable widths instead of compressing properties into desktop columns.
- [Apple Notes](https://support.apple.com/en-us/118442): retain familiar search and direct note creation. Blue uses a flat library of notes and collections, with no folder hierarchy or predefined collection templates.
- [Craft](https://www.craft.do/): use restrained typography, content as the primary surface, and structured collections within a notes product. Avoid its broader workspace/task vocabulary for this release.
- [ThatPet](https://thatpet.app/): the useful principle is distinct reactions for listening, thinking, searching, working and completion. Blue's original character is drawn with SwiftUI paths and uses different eyes, arm poses and a search gesture; it does not reuse ThatPet artwork.
- [Apple Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub): Xcode 27 replaces the older standalone Simulator UI with Device Hub. The simulator runtime and simctl still provide reproducible build/test/install commands.

White/black system surfaces, secondary gray, and system typography handle both appearances. Blue identifies the character; custom indicators use their chosen accent color. Use system Liquid Glass for native navigation and restrained material for the assistant dock. Editors are pushed screens; only filters, property configuration and Settings need modal context. A modal has one close control.

Status filters use choices, ratings use a minimum slider plus optional maximum, numeric fields use numeric bounds, booleans use the same visual indicators as rows and detail, dates use a native date picker, and text/tags use matching text. The collection shows active removable chips with their current values, plus overflow removal and Clear All. The collection options menu and icon filters stay in a compact strip above the list, with 44-point targets on compact phones. Sorting is independent of filters. Hearts mean Like, stars mean Favorite, and a number means Rating. Optional values stay absent until populated.

At accessibility text sizes, number labels and values stack vertically, filter sheets use full height, and a native date picker replaces the crowded month grid. Accessibility requirements are enforced in AGENTS.md. Simulator screenshots and UI tests are recorded in `docs/verification.md`; a VoiceOver listening pass and real-device interaction remain distinct from automated accessibility audits.

## Current interaction direction

The latest user decision is notes and collections only. Notes open in rendered Markdown with a pencil action for editing. Collections are ordered item lists that adapt through conversation; the creation form has no domain templates. Existing folder data is migrated without losing content.

Library scopes use recognizable icons. Each collection indicator has a user-defined meaning, symbol/emoji and color; it uses the same component in list rows, detail and filters. Inactive indicators are pale gray, selected indicators show their color. Filters such as Favorite are the star itself, with a second tap removing the filter. All populated fields remain visible rather than hiding everything after the first two properties.

The assistant input is a single-line send field, with a microphone action and resumable reply. Enter sends. Tapping outside or switching tabs collapses the chat and dismisses its keyboard without clearing the draft. Native manual controls remain available when the model or speech assets are unavailable.
