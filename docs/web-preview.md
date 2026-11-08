# Blue Safari preview

Live private Site: https://blue-iorb-mobile-20261108.ablazecloak.chatgpt.site

Open it in Safari and sign in with the ChatGPT account that owns this Site. To place it on the iPhone Home Screen, use Share → Add to Home Screen. This is a web preview, not a native installation. No paid Apple Developer Program, TestFlight, App Store Connect, distribution certificate or signing secret is used.

## What is included

Notes with rendered Markdown and manual editing; adaptable collections; all populated item properties; favorites and custom emoji/SF Symbol equivalents in rows, details and visual filters; typed manual item editors; English and Spanish; sorting and filters; undo; JSON export and restore; Enter-to-send and tap-outside chat dismissal; browser dictation where supported. Creation has no predefined templates or folders. At the user’s explicit request, this owner-private Site now imports the existing native library once: six collections, 27 items and two notes. It preserves existing browser content and never reapplies the same import after deletions.

The calendar offers a month grid, daily agenda, editable timed or all-day events, colors and undo. Collection date fields also appear in the agenda and open their items. Calendar events are browser-local plans; they do not schedule native alarms or notifications. AI calendar creation is not implemented in this preview.

The web library lives in this browser's local storage. It is separate from the native SwiftData library and from other browsers. Export a backup before clearing browser data. Editor drafts are cached in the tab session and chat drafts in local storage. The Home Screen installation has no offline service worker. Safari or iOS may give a Home Screen app separate browser storage; use export/restore when moving between them.

## AI preview connection

AI runs through the existing genuine Apple Foundation Models bridge on this Mac. The Worker requires the authenticated Site owner and a same-origin request. It forwards a validated web-library snapshot to an authenticated Node gateway through an HTTPS Cloudflare Quick Tunnel. The gateway listens on loopback, validates a bearer token in constant time, limits the body to 2 MB, allows one active request, and forwards only `/respond` to the Mac model. It does not expose native library files or log prompts or library contents. The model operates on the supplied web snapshot in an ephemeral store.

Runtime secret names are `BLUE_MODEL_BRIDGE_URL`, `BLUE_MODEL_BRIDGE_TOKEN` and `BLUE_LIBRARY_IMPORT`. The last value is a compressed native snapshot, kept exclusively in the private Site’s runtime secrets. The authenticated, same-origin `/api/library-import` endpoint returns it with no-store caching. Import does not require the Mac to remain awake. Source code, public assets and deployment archives do not contain the snapshot. They are configured only in Sites and in an ignored local `.dev.vars` file for development. The local token is in ignored `.build/model-bridge-token`. No secret value is in Git, client code, this document or GitHub Actions.

The running launchd jobs are:

- `app.iorb.blue.model-bridge` — the existing simulator/Mac bridge on 127.0.0.1:7977.
- `app.iorb.blue.web-model-gateway` — the preview-only gateway on 127.0.0.1:7978.
- `app.iorb.blue.web-model-tunnel` — temporary HTTPS tunnel to the gateway.

Keep the Mac awake and online for AI requests. The temporary tunnel has no uptime guarantee and changes its URL after restart. If restarted, read the new URL from the ignored tunnel log, update the corresponding Sites runtime secret and redeploy the saved version. Manual editing remains usable in a loaded page when the model is unavailable.

To stop the web connection:

```sh
launchctl remove app.iorb.blue.web-model-tunnel
launchctl remove app.iorb.blue.web-model-gateway
```

The native app's Release/device code still performs on-device inference. This remote preview gateway is not embedded in native distribution builds. Browser speech recognition follows the browser's service and permissions; it is not claimed to be on-device. Native alarm delivery and cross-device sync are outside this preview.

## Verification on 2026-11-08

The initial Sites source commit `18b6cdf3d8f6885ffb882f031f03d222947bb683` built and deployed as version 1. Version 2 uses source commit `21a932898d1ead9b164b129c0658fc7c5a9e70c2` and corrects note-versus-record chat context. The public multi-platform repository contains the same app source under `web/`.

- Clean dependency installation, TypeScript checking, three domain/validation tests and production Worker build passed. Tests cover malformed imports, UUID identity, unknown or mistyped fields, favorites, custom indicators, numeric/date filters, missing-value sort order and unsafe links.
- HTTP checks rejected unauthenticated requests (401), malformed authenticated payloads (400) and unauthenticated tunnel requests (401).
- The compiled production Worker was also run locally with explicit runtime secret bindings. It created a note through the real Mac model in 2.86 seconds. The note-edit check exposed missing explicit edit/replace verbs and unreliable routing of requests about the open note. After those fixes, the model replaced the requested sentence in the same note, increased its revision and preserved the Markdown heading. It omitted the requested new bold markers; exact inline-format obedience remains a model-quality limit. The web client also avoids sending an earlier item as context while a note is open. The first local production attempts correctly returned 503 while those runtime bindings were absent; adding the ignored local bindings resolved this. Hosted runtime secrets were already configured before publication.
- Browser QA at desktop size and 390 × 844 verified manual note creation, rendered Markdown/checklists, favorites, persistence after reload, collection navigation, Enter-to-send, outside-click dismissal, English/Spanish switching, and the same indicators in rows, details and filters.
- Genuine model requests created a Movies collection, captured Interstellar, added a purple 🗿 indicator and 🚬 collection icon, staged and applied removal of a populated Title field, and filled director Christopher Nolan and release year 2014 from public Wikipedia results. All observed values were stored in the browser library.
- One compound request created the collection without adding the item. A subsequent explicit capture request added it. Generated bilingual labels may translate user-specified meanings. These are model-quality limits; tool results show actual saved state and do not claim unperformed changes.
- Production publication succeeded and the public URL showed its private ChatGPT login gate. The embedded browser had no signed-in ChatGPT session, so the authenticated production AI flow remains to be tried by the owner. Local browser tests used the starter's development identity and the real deployed tunnel/model.

Local screenshot: `artifacts/blue-web-mobile.jpg` shows synthetic test data. Physical iPhone Safari, microphone permission/recognition and Home Screen installation have not been tested on the user's device. This preview is independent of the native simulator checks in `docs/verification.md`.

## Calendar and compact interface update

The page now opens directly on content, with icon navigation for library, collections, notes and calendar. Promotional headings, the footer slogan and repeated chat guidance were removed. New-item controls sit beside their relevant section headings; favorites remain a visual star filter. Native TV, food and restaurant symbols have proper web equivalents.

The migration matches stable identities and bilingual collection names, maps status choices without changing existing meanings, and fills missing values while preserving browser values and custom icons. A marker is saved atomically with the merged library and retained in exports and AI responses. Calendar data is also retained across native model responses. An unreadable existing library is not overwritten by import.

Validation: TypeScript, six domain tests (including a non-European timezone), and the production Worker build passed. The real native snapshot validates and imports all six collections, 27 items and two notes. Browser QA at 390 × 844 verified automatic import into an existing browser library, preserved local notes/icons, no duplicates after reload, calendar navigation, timed event creation/editing, deletion/undo and persistence. Native CI for commit `6a3295a` also completed successfully before this web-only change.

The compiled production Worker returned 401 without identity, 403 for a different origin, and 200 with the full validated import for the local authenticated test identity. Its real Mac model created a verification note in 3.8 seconds while preserving calendar events and the one-time import marker. Source and build scans found neither runtime secret values nor the private import snapshot. Desktop layout was inspected at 1200 × 900 with no horizontal overflow. The hosted owner login flow and physical iPhone remain user-side checks.

Published version 3 uses Sites source commit `afd3e84b806db945f8125b6b91b3ec20e764b264`. The private Site URL is unchanged.
