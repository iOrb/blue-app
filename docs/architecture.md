# Architecture

Blue has a native SwiftUI iPhone app (iOS 26+) and an owner-private browser preview. The public repository is iOrb/blue-app. The native assistant calls OpenAI, Gemini or Grok directly using the user's own API key. The separate owner-private web preview still uses its development Mac bridge.

## Persistence

Domain values are Codable and Sendable. Collections have stable semantic field IDs and typed values; records and standalone Markdown notes remain distinct. Field metadata includes optional option icons, inactive status, numeric bounds and step. Favorites are independent of the collection schema. Legacy payloads without new optional metadata still decode.

LibraryStore owns the MainActor SwiftData context. The versioned V1 entity schema stores independently keyed JSON payloads. Calendar events use the new `event:` payload kind without changing the underlying SwiftData entity layout. Existing snapshots missing events decode, and old stores are not reseeded. Legacy folders flatten while preserving IDs and content.

A mutation builds candidate state, explicitly saves changed payloads, then publishes observable state. Failure rolls back. Records, notes and events use optimistic revision checks. Deletion proposals retain the read revision; collection deletion and field-removal proposals also retain record revisions and the original schema. Undo state and restoration are removed. Queries and payload diffing currently run on the main actor; this is a personal-library implementation, not a paginated database.

## Semantic assistant

Legacy JSON payloads may contain an archive flag. The decoder ignores the retired flag and loads the entry into its normal library view. Bulk record deletion validates every selected revision and collection ID before removing the selection in one store transaction. During selection, the collection screen supplies a temporary action bar in place of the native tabs.

The native assistant stores the selected provider and model in preferences and its key in the device-only Keychain. Requests go directly to the chosen provider. Each chat request starts with bounded conversation and IDs for open entries. The model can look up paginated titles, read exact fields and body pages, or show a saved value directly. Search uses a separate provider call that receives only the public query.

The iPhone decodes tool calls and validates IDs, revisions and field values before committing. A clear request can create, update or delete a named entry directly. Removing a populated field still opens a review. Independent library changes can commit together. Events and alarms go through the system scheduling adapter. Existing Foundation Models tools remain available to the owner-private web bridge and Mac harness.

## Calendar and alarms

CalendarEvent persists timed and all-day plans with a color, notes, notification preference and revision. A future timed event requires a local notification and an AlarmKit alarm. Past events persist as history, and moving a future event to the past cancels both pending alerts. The service schedules the notification before committing the alarm and event together. If the alarm or store operation fails, it compensates the notification and preserves the existing saved revision. The calendar editor can link a future timed event to an AlarmKit system alarm using the same UUID. AlarmService saves both values in one store transaction after system scheduling succeeds. Editing or deleting the linked event updates or cancels its alarm. Failure paths preserve or compensate the system state. The Mac adapter rejects system-alarm scheduling. Physical delivery/Focus/recurrence checks must be performed on an iPhone.

## Presentation and web preview

Features mutate through LibraryStore. The native root owns navigation, assistant and alarm services. A native TabView presents three sections inside a shared navigation stack. The prominent Blue tab action presents the composer while retaining the current section. The system bar hides beneath presentations and the floating Blue button remains inside collections. Section title and actions share a fixed header; collection back/options and detail sheet controls also stay fixed while content scrolls. Notes use plain text and retain the Codable markdown key for compatibility. Notes and collection records autosave valid inline edits. Event sheets keep edits in a draft and commit through AlarmService when the user taps the checkmark. Destructive actions use a centered modal and revalidate revisions before committing. The web mirror uses React and browser-local versioned JSON, with validation before storage/state publication. A one-time authenticated private import preserves the owner's existing native lists; private snapshots and credentials never enter Git or the deployment archive.

Native SwiftUI sheets use the system transition, a compact detent based on content when measured. Event editors use the compact detent, while other sheets can expand. The tab bar remains mounted behind the sheet. The composer reads the saved provider and Keychain credential on opening. Settings validates changed credentials and models through the catalog. The catalog request sends no library context. Missing and rejected credentials route to the highlighted provider controls. DEBUG fixtures support library search and the voice UI.

Connected chat and voice share guidance for colloquial phrasing, spelling mistakes, mixed languages, and corrections. When literal title lookup has no matches, it can return a bounded list of possible saved titles in the requested scope for the model to compare. OpenAI library chat reads a completed structured response on supported models. An invalid action format can be retried once. Store validation still controls edits.

Live voice uses an ephemeral URLSession WebSocket and AVAudioEngine. OpenAI defaults to GPT-Live 1. It handles ordinary conversation itself and uses Responses delegation with the configured text model for requests that need tools. Gemini Live, Grok Voice and the optional OpenAI Realtime model call the same typed tools directly. The app validates arguments and revisions before local execution. Deletion is staged for review. Alarm and reminder requests use the same event actions as calendar requests. The public event fields are name, day, time, weekly repeat and notes. Typed arguments reject other event attributes. Clock components resolve to the next local occurrence unless a day is specified. Weekly events use the chosen weekdays and local time, with the next occurrence as their stored date. Success requires both AlarmKit and notification scheduling and the store save.

The audio session activates off the main actor. Blue waits for a microphone packet before playing the ready tone and reports a stalled capture stream. The engine connects the mixer explicitly to the output node. Blue uses system echo cancellation when supported. On built-in speaker routes without it, Blue suppresses capture during playback and a brief echo tail. Silence does not begin a speaking turn. Audio and tool queues are bounded. Muting removes the input tap, and closing or backgrounding the surface stops capture. Dictation in text chat records a temporary file, transcribes it through the selected provider, and deletes it after transcription or cancellation.

Native Settings imports collections and notes from a version 2 or 3 export in a single store transaction. Existing collections, records and notes keep their values. The same importer supports an explicit DEBUG device restore from an app-local file. Personal exports are separate from app source and builds.

The web Worker authenticates the owner and proxies bounded requests to the token-protected Mac bridge. The bridge uses the production store/tools against an ephemeral library snapshot. The client rejects intervening edits before applying a response. Browser import markers are preserved; calendar events now round-trip through native inference. Browser and native stores do not continuously synchronize.

Device/Release binaries exclude the DEBUG loopback bridge. The paid distribution plan uses internal TestFlight and Xcode Cloud with Apple-managed signing. Local Xcode installation remains a development fallback; see docs/release.md for activation status.

## Event payload v3, covers and folder copies

The SwiftData entity schema remains V1. The explicit `metadata:eventsVersion` payload migration converts standalone legacy alarms to CalendarEvent values with the same UUID. Existing event notes and linked alarm schedules are preserved. Optional weekday and collection artwork fields decode old payloads without reseeding. SavedAlarm rows are private scheduling adapters for the corresponding event, not a separate UI or assistant entity.

CalendarEvent weekly recurrence uses Foundation calendar weekdays (Sunday 1 through Saturday 7). The service validates unique in-range values, schedules AlarmKit weekly relative alarms and one repeating UNCalendarNotificationTrigger per selected weekday, and restores prior notification configuration when an edit fails. Calendar rows and day markers evaluate the recurrence rule. Deleting a series cancels its alarm and every corresponding notification identifier.

CollectionArtwork stores a UUID and bounded JPEG bytes in the collection payload. ImageIO normalizes chosen or generated images to at most 768 pixels and one megabyte. Presentation caches decoded covers. The native Photos picker reads only the chosen image. Optional generated covers use the saved OpenAI key directly, with the available Flare model preferred. One explicit Generate action requests four variants. Only the visible description and style are submitted. No library contents are sent for image generation. Provider API credentials enter only the authenticated encrypted app snapshot, never plaintext exports.

FolderBackupService is legacy transport; automatic plaintext folder copies and the picker are disabled. Existing files are preserved. Current optional encrypted Drive backup is described below and in docs/backup-format.md. Manual JSON export is explicit and unencrypted.

## Multi-step assistant and persistent live ownership

The connected text agent can continue after a committed create/update/batch, feeding the saved result into its next bounded tool turn (up to 16 turns). Identical completed mutation payloads are not applied twice. Each turn refreshes the store snapshot; event mutations retain omitted fields and continue through AlarmService. Independent event operations are sequential, not one transaction across AlarmKit and SwiftData; earlier successful changes remain committed if a later operation fails.

AssistantService owns the live voice service so transient AssistantDock reconstruction does not create a new audio session. Closing the assistant explicitly stops its audio; backgrounding stops audio, and returning foreground or ending an interruption can restart it. Response-level failures keep the transport open while actual session closure remains an error. Provider behavior and physical microphone continuity require device checks.

## Native Google Drive sign-in

GoogleDriveConnection implements native ASWebAuthenticationSession with one-use PKCE/state, token exchange, Keychain-only credential storage and refresh on restoration. It verifies the Drive scope and a Drive about request before showing a connected account. project.yml owns the public OAuth client ID and callback scheme. A connection must include both required scopes before the optional encrypted Drive uploader can run. Complete restore UI and device alarm reconciliation remain unfinished. No Google tokens are written to app preferences or logs.

## Google Drive snapshot upload (16 November 2026)

BlueRoot owns one GoogleDriveConnection and DriveBackupService and injects them into Settings. Optional authorization now requests drive.file plus drive.appdata. Old drive.file-only connections show Enable Drive backups, requiring fresh user consent before uploads. DriveBackupService coalesces commits/preferences/provider-key changes and serializes snapshots. It writes one account-protected AES-GCM file per installation and verifies uploaded bytes. Keys live separately in Blue's appDataFolder; this is account-protected encryption rather than encryption against Google. A reader for another compatible Blue client is available, but a full restore UI and OS scheduling reconciliation are not implemented. See backup-format.md for the versioned portable format and limitations. Existing copies from other installations and unreadable copies are preserved.
