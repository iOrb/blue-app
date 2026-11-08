# Architecture

Blue is a local-only SwiftUI application for iPhone, iOS 26 or later. There are no runtime third-party packages, backend services, telemetry, cloud inference, or network-fetched model weights. Apple manages the availability of its on-device model.

## Persistence and values

`Domain` contains Sendable/Codable values: folders, collections, records, notes and alarms. Collection fields have stable semantic IDs and typed values. Notes and written record notes remain separate from ratings. Built-in labels reference string catalog keys; user text is preserved verbatim; model-created properties have editable English and Spanish labels.

`LibraryStore` owns a MainActor SwiftData context and a narrow observable library value. The versioned V1 schema stores independently keyed entity payloads, including an initialized marker. It fetches once on startup and saves only changed payloads in a transaction. A failed save rolls back without publishing the candidate state. Optimistic record/note revisions reject concurrent stale edits. The initialized marker prevents reseeding after deletions. V1 is the initial schema; future versions must declare migration stages instead of resetting data.

The current implementation encodes the in-memory entity set to identify changed payloads on each mutation. This favors simplicity and predictable rollback for personal libraries. Stress measurements determine when to replace this diff with explicitly tracked dirty IDs. Do not claim it is a paginated database. The bounded ten-step undo history excludes system alarm restoration. Collection queries above 500 records run on a cancellable detached task with a Sendable snapshot; stale results are not published. Small personal lists use the same pure query synchronously.

Export is UTF-8 JSON, `formatVersion: 1`, with ISO8601 dates, UUID references, semantic field IDs, tagged typed values, and Markdown separated from property values. Export is explicit through the system file picker. No import or cloud sync is included in this first version.

## Assistant

Each request uses typed on-device intent classification to choose the records, collections, notes or alarms area, then creates a fresh Foundation Models session exposing only that area's one or two tools. This keeps the context bounded and reduces unrelated tool selection. Both stages use Apple's local model and share cancellation; the action stage has a request-local tool ledger. Read questions and negated instructions cannot authorize writes. Write tools require an explicit recognized English or Spanish action word (for example change/set/create or cambia/ponle/crea); unknown phrasing fails closed and can be rephrased or handled manually. Every tool context starts with mutations disabled. Genuine production inference uses only `SystemLanguageModel.default`. Tool arguments are typed. Swift validates identities, read revisions, field types, numeric limits, collection schemas, weekday ranges and future alarm times. A request reserves at most one mutation before an asynchronous platform call starts, preventing concurrent tool calls from bypassing the ledger. Ambiguous reads do not grant edit authorization. Cancellation invalidates further tool calls and old request completions cannot overwrite a replacement request; completed writes remain visible even if subsequent generation fails. The UI renders committed records and actions rather than an unconstrained model claim of success. Tools cover record reads/edits, typed collection creation, validated filtered collection views, note search/creation, and alarm lookup/creation/deletion confirmation. There is no general-purpose code execution tool.

A DEBUG-only deterministic assistant exercises exact-record reads/edits and custom hiking collection creation. It is selected only with `--test-assistant`, is labeled in Settings, and is compiled out of normal Release. Its results are never reported as evidence of real inference. The real-model integration test uses the production tools with a deterministic alarm adapter and is opt-in separately from CI.

## Alarms

`AlarmService` owns the system boundary through `AlarmScheduling`; tests inject a fake. Production uses AlarmKit authorization, schedules, cancellation and alarm updates. Fixed alarms retain an absolute instant; weekly alarms follow system wall-clock time and Calendar weekdays. Local enabled state is published only after system success. Store failures trigger best-effort compensation. System removals reconcile to disabled local records at foreground and from the update stream. On day/time-zone changes, fixed instants remain fixed and weekly alarm display values preserve their original wall-clock time in the new zone. Revoked authorization produces no enabled system IDs. No countdown UI is configured, so no Live Activity widget extension is required for this scope.

An expired or unavailable system alarm is not silently recreated. Authorization denial and scheduling failure remain visible. Physical-device verification is mandatory for delivery while locked, Focus/silent behavior, recurrence and timezone changes.

## Presentation and language

The two native bottom tabs retain navigation state. The assistant sits above the tab bar. Collections use text rows, optional numeric ratings and consistent like/favorite controls. Query state belongs to collection IDs. Exact-record navigation preserves sort order and removes only filters that hide the requested record.

The `Localizer` observable reads String Catalog-generated resources from the selected language bundle. Changing language updates strings and locale formatting without replacing the root view or its navigation/editor state. User drafts remain unchanged. Unedited built-in demo text can resolve in the new language. Apple-controlled dialogs and keyboard text follow system language, as disclosed in Settings. Native keyboard dictation is available through iOS where enabled; Blue does not record audio or request microphone access.
