# Blue Safari preview

Live private Site: https://blue-iorb-mobile-20261108.ablazecloak.chatgpt.site

Open it in Safari and sign in with the ChatGPT account that owns this Site. To place it on the iPhone Home Screen, use Share → Add to Home Screen. This is a web preview, not a native installation. No paid Apple Developer Program, TestFlight, App Store Connect, distribution certificate or signing secret is used.

## What is included

Notes with rendered Markdown and manual editing; adaptable collections; all populated item properties; favorites and custom emoji/SF Symbol equivalents in rows, details and visual filters; typed manual item editors; English and Spanish; sorting and filters; undo; JSON export and restore; Enter-to-send and tap-outside chat dismissal; browser dictation where supported. New libraries are empty and have no predefined templates or folders.

The web library lives in this browser's local storage. It is separate from the native SwiftData library and from other browsers. Export a backup before clearing browser data. Editor drafts are cached in the tab session and chat drafts in local storage. The Home Screen installation has no offline service worker. Safari or iOS may give a Home Screen app separate browser storage; use export/restore when moving between them.

## AI preview connection

AI runs through the existing genuine Apple Foundation Models bridge on this Mac. The Worker requires the authenticated Site owner and a same-origin request. It forwards a validated web-library snapshot to an authenticated Node gateway through an HTTPS Cloudflare Quick Tunnel. The gateway listens on loopback, validates a bearer token in constant time, limits the body to 2 MB, allows one active request, and forwards only `/respond` to the Mac model. It does not expose native library files or log prompts or library contents. The model operates on the supplied web snapshot in an ephemeral store.

Runtime secret names are `BLUE_MODEL_BRIDGE_URL` and `BLUE_MODEL_BRIDGE_TOKEN`. They are configured only in Sites and in an ignored local `.dev.vars` file for development. The local token is in ignored `.build/model-bridge-token`. No secret value is in Git, client code, this document or GitHub Actions.

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
