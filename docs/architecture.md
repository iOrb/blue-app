# Architecture

Blue has a native SwiftUI iPhone app (iOS 26+) and an owner-private browser preview. The public repository is iOrb/blue-app. Native production inference uses Apple's on-device Foundation Models. A development Mac bridge serves the simulator and web preview; no remote model API or downloaded weights are used.

## Persistence

Domain values are Codable and Sendable. Collections have stable semantic field IDs and typed values; records and standalone Markdown notes remain distinct. Field metadata includes optional option icons, inactive status, numeric bounds and step. Favorites are independent of the collection schema. Legacy payloads without new optional metadata still decode.

LibraryStore owns the MainActor SwiftData context. The versioned V1 entity schema stores independently keyed JSON payloads. Calendar events use the new `event:` payload kind without changing the underlying SwiftData entity layout. Existing snapshots missing events decode, and old stores are not reseeded. Legacy folders flatten while preserving IDs and content.

A mutation builds candidate state, explicitly saves changed payloads, then publishes observable state. Failure rolls back. Records, notes and events use optimistic revision checks. Deletion proposals retain the read revision; collection deletion and field-removal proposals also retain record revisions and the original schema. Undo state and restoration are removed. Queries and payload diffing currently run on the main actor; this is a personal-library implementation, not a paginated database.

## Semantic assistant

Each request starts with writes disabled. A focused Foundation Models decision distinguishes ordinary conversation from saved-content work before any identity resolution. A separate semantic permission decision distinguishes a requested saved change from reading or proposing an edit. The domain decision interprets operation, reference and public-lookup intent. Both permission and operation must authorize a mutation. There are no production command-word, numeric-evidence regex or substring authorization gates. The model resolves named targets against a bounded catalog; open-entity references retain their UI context. Exact IDs, types, input limits, snapshots, cancellation and the one-mutation ledger remain deterministic validations.

The catalog is bounded by entity count and characters. `readLibrary` offers paginated title/ID browsing and exact content reads. Requested field IDs are validated against saved schemas. Read-only results render actual saved values instead of free-form model guesses. Standalone note edits use model-generated text block replacements, preserving unrelated blocks. Creation, item edits, schema changes, public enrichment and calendar changes use typed tools. All entity deletions and all field removals are proposed for review.

The assistant keeps at most four session-only exchanges (800 user characters and 1,000 reply characters each). Conversation uses explicit prompt/response transcript roles; follow-ups can resolve a prior concrete proposal. Saved-result summaries come from the store. The history is not persisted in the library or logged. Web request/response boundaries validate its shape and bounds. A proposal reads the exact selected content without granting mutation permission. Suggested note replacements carry the exact candidate text and source revision in session context (at most 20,000 characters per candidate). Semantic acceptance applies that candidate directly, with a fresh exact read and revision validation; it does not regenerate a different rewrite.

Foundation Models is probabilistic and has a limited context window. Unsupported, ambiguous or incomplete changes return a localized explanation; no success is inferred merely from generated prose. Tests distinguish actual local-model runs from the DEBUG-only deterministic UI double. Public facts use Wikipedia titles only; private note text is never passed to lookup. Sources are retained separately from personal values.

## Calendar and alarms

CalendarEvent persists ordinary timed/all-day plans with a color and revision. It never schedules an alarm. AlarmService uses AlarmKit with explicit authorization, scheduling, cancellation and reconciliation. Enabled state is saved only after system success; save failures trigger compensation. The Mac adapter rejects system-alarm scheduling. Physical delivery/Focus/recurrence checks must be performed on an iPhone.

## Presentation and web preview

Features mutate through LibraryStore. The native root owns navigation, assistant and alarm services. A native TabView presents three sections inside a shared navigation stack. The prominent Blue tab action presents the composer while retaining the current section. The system bar hides beneath presentations and the floating Blue button remains inside collections. Section title and actions share a fixed header; collection back/options and detail sheet controls also stay fixed while content scrolls. Notes use plain text and retain the Codable markdown key for compatibility. Valid inline edits autosave. Destructive actions use a centered modal and revalidate revisions before committing. The web mirror uses React and browser-local versioned JSON, with validation before storage/state publication. A one-time authenticated private import preserves the owner's existing native lists; private snapshots and credentials never enter Git or the deployment archive.

The native Blue composer can search saved titles and note text without a model. This local search reads library items and opens their editors. Speech permission completion can arrive off the main actor. Dictation handles it in a Sendable callback and returns to the main actor to start capture. The audio tap runs on the audio queue.

Native Settings imports collections and notes from a version 2 export in a single store transaction. Existing collections, records and notes keep their values. The same importer supports an explicit DEBUG device restore from an app-local file. Personal exports are separate from app source and builds.

The web Worker authenticates the owner and proxies bounded requests to the token-protected Mac bridge. The bridge uses the production store/tools against an ephemeral library snapshot. The client rejects intervening edits before applying a response. Browser import markers are preserved; calendar events now round-trip through native inference. Browser and native stores do not continuously synchronize.

Device/Release binaries exclude the DEBUG loopback bridge. Signing is local with a free Personal Team; there is no TestFlight or paid distribution pipeline.
