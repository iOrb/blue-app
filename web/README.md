# Blue web preview

A private Safari preview of Blue's notes, adaptable collections, Markdown and visual indicators. The native iPhone app lives in the parent repository; this preview has its own browser-local library.

## Run

Use Node 22.13 or newer (Node 25 was used for verification).

```sh
npm run install:ci
npm run dev
npm run typecheck
npm test
npm run build
```

The development server prints its local address. The Sites development sign-in flow creates a local test identity; production access is restricted to the Site owner through ChatGPT sign-in.

For genuine AI, create an ignored `.dev.vars` file containing `BLUE_MODEL_BRIDGE_URL` and `BLUE_MODEL_BRIDGE_TOKEN`. Configure the same keys as secret runtime values in Sites. Never put values in source, client code, GitHub Actions, or the hosting manifest. The URL points to the authenticated preview gateway in the parent repository. No paid Apple developer membership, distribution credentials or third-party model API key is needed.

## Data and behavior

- New libraries start empty. Notes show only their titles in the overview and render Markdown when opened. Collections start as simple lists; Blue can adapt fields and indicators.
- Local storage keeps the web library on this browser. Export and restore version-2 JSON backups from Settings. This does not sync with native SwiftData or another browser. Dates use Apple's Codable reference epoch (2001-01-01).
- The entire web library snapshot is sent through the authenticated Site to the Mac model for each AI request. Inference runs on the Mac. Public enrichment can send public topic titles to Wikipedia. The gateway does not log prompts or library contents.
- AI changes are validated before applying them. Concurrent library edits invalidate a pending response. Removing fields and deleting content requires confirmation. There is no Undo history.
- Enter sends, Shift+Enter inserts a newline, and tapping outside chat dismisses it while preserving the draft. Browser speech recognition is used where supported; otherwise use keyboard dictation.
- Tap titles and rendered Markdown to edit; valid changes save immediately. Navigation shows Notes, Collections, Calendar and Blue. Filters appear only inside a collection. The calendar plus creates an event, and a day opens its agenda in a sheet.
- The Mac and temporary preview tunnel must remain running. This is a testing connection, not an always-on service. Missing model connectivity is shown explicitly.
- Home Screen metadata is included. There is no offline service worker, native alarm scheduling, or device synchronization.

The Vinext starter's Sites authentication, Worker entry point and packaging integration are preserved. The `@emnapi` overrides keep the optional WebAssembly dependency tree reproducible with npm 11; a clean `npm ci` was verified after repairing the initial starter lockfile.
