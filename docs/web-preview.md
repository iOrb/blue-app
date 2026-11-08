# Private Blue web preview

URL: https://blue-iorb-mobile-20261108.ablazecloak.chatgpt.site

Owner-private access is unchanged. The native app remains in `Blue/`; the sanitized web source is mirrored in `web/`. The editable Sites checkout is ignored under `artifacts/sites/blue-web-20261108`. Version 5 uses source commit `9001c6f46001936ab4338940f12dc36c35d2da31` and was published successfully on 8 November 2026, preserving runtime environment revision 2.

## Behavior

A white canvas, compact rows without separator lines, and only Collections, Notes and Calendar at the root. No brand/Your Space combined view, folder breadcrumbs, global filters, item previews in the collections overview, note subtitles or Undo. Blue floats separately at the bottom right and remains accessible from item/note details. Section navigation hides inside collections and beneath sheets.

Collection back/options stay fixed; its centered editable title, count and left-aligned sort row scroll. Tap the sort criterion to reverse direction. Notes and item bodies use plain text with line breaks; legacy Markdown characters remain literal to preserve data. Detail sheets have a down-chevron, options menu, left-aligned title and centered item properties. Active indicators are filled; inactive ones are pale gray. Numbers use a scrolling picker. Deletion is a red minus at the bottom of the options menu and opens a centered modal with a floating top-right cross.

Valid edits autosave. Sheets dismiss by outside tap, drag or Escape; headings and the Blue composer remain fixed. The Blue sheet has no visible title: mascot and composer sit at the top. Calendar plus creates an event, and selecting a day opens its agenda sheet. Events are not native alarms.

Blue uses semantic intent/identity and typed tools in the native shared model implementation. Exact saved results are displayed in its sheet. It can edit note text, add/remove schema fields, customize indicators, and create/update events; removals are staged. The browser rejects stale responses if its library changed while a request ran. Follow-ups retain the selected record, note or event and four bounded, session-only exchanges. A semantic conversation gate handles greetings without querying a selected item. Read/proposal requests cannot authorize writes.

## Data and connection

Browser localStorage owns each browser's library. Explicit versioned JSON export/import is available. New libraries start empty. The user's existing private native snapshot is provided through the owner-authenticated `/api/library-import` endpoint using the secret `BLUE_LIBRARY_IMPORT`. A stable one-time marker prevents reseeding, duplicates or resurrection of deleted content. It initially supplied six collections, 27 items and two notes; it is not continuous synchronization. No private snapshot is in the public repository or deployment source archive.

The Site forwards a library snapshot through a token-authenticated temporary tunnel to the Mac model. Launchd jobs `app.iorb.blue.model-bridge`, `app.iorb.blue.web-model-gateway` and `app.iorb.blue.web-model-tunnel` keep the testing path running. The Site's `BLUE_MODEL_BRIDGE_URL` and `BLUE_MODEL_BRIDGE_TOKEN` are runtime secrets. The token file and local environment files are ignored. They were preserved when the bridge binary was updated.

The Mac must stay awake and reachable. A changed tunnel URL requires updating the matching Sites secret and redeploying; never publish the token. Manual editing remains available without model connectivity. Browser speech recognition uses the browser's service/permissions and is not claimed to run on-device.

## Verification

TypeScript, nine data/conversation validation tests and the production Worker build pass. The archive and public source mirror were scanned for runtime secret values and the private import payload before publication. Sites confirmed successful owner-private version 5 deployment, preserving environment revision 2. The published Spanish collection was inspected in the authenticated browser; existing user records and custom indicators remained present. Mobile and desktop layouts, fixed controls, filled icons, plain-text details, the top composer and deletion cancellation were inspected.

Four HTTP failure paths reject absent authentication, foreign origin, malformed input and oversized history. The current model-unavailable response preserves the exact synthetic library and returns bounded history. A nine-case conversational Mac integration passed earlier in development, but the final end-to-end rerun is blocked by the Mac's Foundation Models service (`SensitiveContentAnalysisML` 15 / `ModelManagerError` 1013), even on a minimal isolated prompt. It reports availability but generation fails. Do not treat the earlier success as final-model verification. Manual features are working; current AI availability remains a limitation.

Physical iPhone Safari, microphone permission and Home Screen installation remain user-side checks. There is no offline service worker, native alarm delivery or background synchronization in this preview. See verification.md for exact native test results.
