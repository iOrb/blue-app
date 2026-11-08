# Design

Blue uses a white canvas in light appearance, strong system typography and compact rows without separator lines. Dark appearance follows the system. The latest playlist reference informs the title/count/sort hierarchy, not a media player or a dark-only theme.

The root contains only Collections, Notes and Calendar. Collections show names and counts, notes show titles. No combined Your Space screen, folders, breadcrumbs, preview text, Undo or manual icon-filter bar is exposed. A separate Blue character floats at the bottom right of the navigation capsule. Inside a collection only Blue remains; the section capsule is hidden.

Collections have a fixed back chevron and ellipsis menu. The centered editable title, item count and left-aligned sort row scroll with the content. Tapping the current sort criterion toggles ascending/descending. Blue can change the criterion, apply a typed collection query and clear it. The menu offers rename and a red minus/delete action last.

Items and notes open in large, non-full-screen sheets. Their down-chevron and ellipsis stay fixed; content scrolls. Item titles align left and property controls are centered. Favorites use stars, likes hearts, watched uses a filled eye and numeric values open a scrolling number picker. Inactive indicators are light gray; active indicators are filled and colored. User-defined emoji retain their meaning. Empty optional row values stay hidden, and every saved property remains available in the detail.

Notes contain only a title and plain text with line breaks. Editing either saves valid changes immediately; there are no edit or Save buttons. Existing stored Markdown syntax is preserved as literal text, without destructive conversion. Item written content is also plain editable text. Deletion uses a centered modal with a floating cross in the screen's top-right corner, cancel and red minus/delete. Cancelling does not mutate the store.

Blue is also reachable from a note/item detail, carrying its selected identity into the chat. Its sheet covers navigation, has no visible title, and pins the mascot beside the composer at the top. Enter sends, microphone capture is explicit, and recent exchanges/exact results scroll underneath. Outside tap, drag or accessibility escape dismiss sheets; unsent drafts survive. Proposed note rewrites remain unsaved until accepted, and destructive tool changes require review.

Calendar plus creates an ordinary event. A day opens an agenda sheet; events do not ring. Actual ringing alarms are separate AlarmKit operations. Native strings resolve through the English/Spanish catalog. User content and view identity survive language changes. Controls retain accessibility labels and 44-point targets, Dynamic Type and Reduce Motion support. See verification.md for completed checks and hardware limits.
