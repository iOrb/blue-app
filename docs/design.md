# Design

Blue uses a white canvas in light appearance, large system typography, thin separators and compact text rows. Dark appearance follows the system. The reference is the owner's Blue Cuaderno Site; native and web share its spacious, unboxed layout.

Bottom navigation contains Notes, Collections, Calendar and the Blue character. Tapping the brand opens the combined view: collections, then note titles, then calendar. There are no folders, breadcrumbs, global favorites filters or always-open chat composer. Collections show only their names and counts until opened; notes show only titles until opened.

The Blue character opens a bottom sheet with a fixed heading, scrolling results and a fixed composer. Enter sends; microphone capture is explicit. Sheets have no close buttons: the backdrop, drag handle or accessibility escape dismisses them. Chat navigation remains reachable. Exact saved results appear in the sheet rather than automatically jumping to another screen.

Within a collection, shared property controls appear in rows, details and filters. Favorites use stars, likes use hearts; custom emoji/SF Symbols retain their own meaning and color. Inactive controls are pale gray, active controls colored. Existing watched/not-watched schemas display an eye: the inactive option is implicit. Status schemas can supply option icons and an inactive option. Numeric values open a scrolling number picker. Optional bounds/steps are stored with the field. Empty optional text properties are hidden in rows and remain available inside the item.

Tap titles or content to edit. Valid changes save immediately, without an edit icon or Save action. Notes and written item content open as rendered Markdown and enter text editing on tap. Collection schema adaptation is handled by Blue, with no manual Add Indicator or template picker. Deleting entities and removing fields requires confirmation; there is no Undo history or button.

Calendar plus creates an ordinary event. Tapping a day opens its agenda in a sheet, not a section below the grid. Events have a title, local date/time or all-day date, and color. These events do not ring. Actual ringing alarms remain a separate AlarmKit capability.

App-owned native strings resolve through the English/Spanish string catalog. User-authored titles/content remain unchanged when switching language. Controls support accessibility labels, touch targets, Reduce Motion and system appearance. Visual and automated checks are recorded in verification.md; physical-device checks remain separate.
