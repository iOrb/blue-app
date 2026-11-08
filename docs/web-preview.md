# Private Blue web preview

URL: https://blue-iorb-mobile-20261108.ablazecloak.chatgpt.site

Owner-private access is unchanged. The native app remains in `Blue/`; the sanitized web source is mirrored in `web/`. The editable Sites checkout is ignored under `artifacts/sites/blue-web-20261108`. Version 4 uses source commit `e3554f97d1a27f98f969fb1ea051d69dfef64d09` and was published successfully on 8 November 2026, preserving runtime environment revision 2.

## Behavior

A white canvas, simple rows and floating bottom navigation for Notes, Collections, Calendar and Blue. The brand opens the combined view, with the calendar after note titles. No folder breadcrumbs, global icon filters, item previews in the collections overview, note subtitles, Undo, or edit/save/close buttons. Collection indicators share their meaning, icon, active color and inactive gray across rows, detail and collection-only filters. Numbers use a scrolling picker.

Tap titles or rendered Markdown to edit; valid changes persist immediately. Deletion requires confirmation. Sheets dismiss by outside tap, drag or Escape, with fixed headings and composer. Navigation remains directly available while Blue is open. Calendar plus creates an event, and selecting a day opens its agenda sheet. Events are not native alarms.

Blue uses semantic intent/identity and typed tools in the native shared model implementation. Exact saved results are displayed in its sheet. It can edit Markdown, add/remove schema fields, customize indicators, and create/update events; removals are staged. The browser rejects stale responses if its library changed while a request ran. Follow-ups retain the selected record, note or event.

## Data and connection

Browser localStorage owns each browser's library. Explicit versioned JSON export/import is available. New libraries start empty. The user's existing private native snapshot is provided through the owner-authenticated `/api/library-import` endpoint using the secret `BLUE_LIBRARY_IMPORT`. A stable one-time marker prevents reseeding, duplicates or resurrection of deleted content. It initially supplied six collections, 27 items and two notes; it is not continuous synchronization. No private snapshot is in the public repository or deployment source archive.

The Site forwards a library snapshot through a token-authenticated temporary tunnel to the Mac model. Launchd jobs `app.iorb.blue.model-bridge`, `app.iorb.blue.web-model-gateway` and `app.iorb.blue.web-model-tunnel` keep the testing path running. The Site's `BLUE_MODEL_BRIDGE_URL` and `BLUE_MODEL_BRIDGE_TOKEN` are runtime secrets. The token file and local environment files are ignored. They were preserved when the bridge binary was updated.

The Mac must stay awake and reachable. A changed tunnel URL requires updating the matching Sites secret and redeploying; never publish the token. Manual editing remains available without model connectivity. Browser speech recognition uses the browser's service/permissions and is not claimed to run on-device.

## Verification

TypeScript, seven data/validation tests and the production Worker build pass. Tests cover invalid libraries, shared field metadata, type-compatible schema migrations, filters, favorite/indicator values, native import reconciliation, calendar time zones and events.

Production Worker HTTP tests rejected unauthenticated, cross-origin and malformed requests (401/403/400). Five real model flows passed through the Worker and tunnel: named exact lookup, targeted note edit, event creation, event follow-up move and custom collection/indicator icons. Browser QA at desktop and 375 × 812 verified title-only overviews, rendered Markdown, autosave/reload, deletion cancellation, calendar day sheets, direct navigation out of chat, preserved drafts and Enter-to-send. The final query displayed only the requested stored rating. Screenshots are in `docs/screenshots/web-assistant.png` and the ignored artifacts directory.

The source archive was scanned for runtime secret values and the private import payload before publication. Sites confirmed successful private deployment. The published page loaded in the available signed-in browser session and its actual Enter-to-send query returned Interstellar’s stored rating. Physical iPhone Safari, microphone permissions and Home Screen installation remain user-side checks. There is no offline service worker, native alarm delivery or background synchronization in this preview.
