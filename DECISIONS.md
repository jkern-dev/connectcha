# Decisions

Choices the spec and plan didn't settle, made during the build. Newest at the bottom.
Format: context, options with their main tradeoff, what was chosen and why, how hard it is to reverse.

---

- **D-01: Generate the Xcode project with XcodeGen** (2026-10-31, M0)
- Context: There is no Xcode GUI in an autonomous build, and a hand-written `project.pbxproj` is unreadable in review and merges badly.
- Options considered: (a) Commit a hand-maintained `.xcodeproj`: no extra tool, but opaque diffs and easy to corrupt. (b) XcodeGen with a `project.yml`: one Homebrew install, human-readable spec, project regenerated on demand. (c) Swift Package-only app: not supported for an app with an extension target.
- Chosen: (b). `ios/project.yml` is the source of truth; the `.xcodeproj` is gitignored and `make ios-project` regenerates it.
- Reversibility: Easy. Commit the generated project and delete the YAML at any time.

- **D-02: Hand-written US phone normaliser instead of PhoneNumberKit** (2026-10-31, M0/M1)
- Context: The plan lists PhoneNumberKit for parsing. The product accepts only US numbers (spec 2) and treats numbers without a country code as US (spec 4.2).
- Options considered: (a) PhoneNumberKit: handles every country, but adds a large dependency and metadata bundle for a product that only needs "is this +1 and ten digits". (b) A ~60-line normaliser: digits only, strip `011` international prefix, 10 digits → +1, 11 digits starting with 1 → +1, anything else with a `+` is non-US. Fully unit-tested.
- Chosen: (b), per the "fewer dependencies" rule in the build brief. Non-US detection only needs to be good enough to show the "country code isn't accepted yet" message; the server refuses non-US numbers regardless (D-03).
- Reversibility: Easy. The normaliser is one type behind one function; swapping the implementation touches nothing else.

- **D-03: Refuse non-US sign-ups server-side with an Auth hook** (2026-10-31, M0)
- Context: The plan relies on Twilio Verify Geo Permissions for scenario 10. Locally there is no Twilio, and GoTrue creates the `auth.users` row *before* it attempts the text, so a refused text still left a phone-hashed profile behind.
- Options considered: (a) Twilio Geo Permissions only: no code, but unenforceable locally and leaves orphan rows. (b) A `before_user_created` Auth hook (a Postgres function GoTrue calls) that rejects any phone not matching `1` + ten digits: enforced in every environment, testable in pgTAP, and no row is created.
- Chosen: (b) in addition to (a). Twilio Geo Permissions remain the cost control against SMS fraud.
- Reversibility: Easy. Disable the hook in `config.toml`.

- **D-04: Placeholder Twilio provider for local development** (2026-10-31, M0)
- Context: GoTrue disables phone login entirely unless an SMS provider is enabled, even when every number is a fixed-code test number.
- Options considered: (a) Enable Twilio with obviously fake credentials; test numbers never reach it. (b) Run a fake SMS webhook provider: more moving parts for no benefit.
- Chosen: (a). The token comes from an environment variable that the Makefile sets to `placeholder-local-only`.
- Reversibility: Trivial. Production uses the dashboard's Twilio Verify settings.

- **D-05: Minimal profiles are readable only through a relationship, not by anyone** (2026-10-31, M0)
- Context: The plan says `profiles_minimal` is readable by any signed-in user and relies on IDs being unguessable. A plain `select * from profiles_minimal` would still list every user, which is a directory and conflicts with principle 3.
- Options considered: (a) Readable by all, rely on UUIDs: simplest, but one query enumerates everyone. (b) A `can_see_profile` helper: you can read a person's name and photo only if you are them, follow either way, have a request either way, or share a conversation. Matched contacts come back from `match_contacts` directly, so no extra access is needed there.
- Chosen: (b). Every screen that shows a name already holds one of those relationships; the match list carries its own names.
- Reversibility: Moderate. Loosening is one view change; the client would not change.

- **D-06: Avatars are `media` rows, not a bare object key** (2026-10-31, M0)
- Context: The plan has `profiles.avatar_key`. Every other image reaches the client through `get-media-urls` by media ID.
- Options considered: (a) `avatar_key` string plus a special case in the URL function. (b) `avatar_media_id` pointing at a `media` row with `usage = 'avatar'`, readable by any signed-in user who holds the ID.
- Chosen: (b). One upload path, one URL path, one cache.
- Reversibility: Easy.

- **D-07: Swift 6 language mode with main-actor default isolation** (2026-10-31, M0)
- Context: Xcode 26 offers "approachable concurrency": code is main-actor isolated unless marked otherwise, which suits a SwiftUI app and keeps strict concurrency checks on.
- Options considered: (a) Swift 5 mode: fewer errors now, no data-race safety. (b) Swift 6 with nonisolated default: many annotations in UI code. (c) Swift 6 with `MainActor` default and `nonisolated` for the notification extension and media pipeline.
- Chosen: (c).
- Reversibility: Easy per target (one build setting).

- **D-08: Local analytics (Logflare) container disabled** (2026-10-31, M0)
- Context: The local Supabase analytics container uses a lot of memory on a 16 GB Mac that also runs two simulators and Xcode. The plan's "privacy log check" used the Studio Logs Explorer, which depends on it.
- Options considered: (a) Keep it on: Studio logs work, less memory for simulators. (b) Turn it off and do the privacy log check with `docker logs` on the API gateway, database and Edge Runtime containers.
- Chosen: (b). `scripts/privacy-log-check.sh` performs the check (M3).
- Reversibility: Trivial (`[analytics] enabled = true`).

- **D-09: Test helpers and demo data live in seed files, never in migrations** (2026-10-31, M0)
- Context: pgTAP tests need to create auth users and impersonate them. Putting those helpers in a migration would ship them to production.
- Options considered: (a) Helpers in a migration guarded by role: still present in production. (b) Helpers in `supabase/seed/00_test_helpers.sql`, which only runs on local and CI resets.
- Chosen: (b). Demo personas follow the same rule in `supabase/seed/10_demo.sql`.
- Reversibility: Trivial.

- **D-10: Demo personas and the "two phones"** (2026-10-31, M0)
- Context: The brief asks for six or more personas across two simulated phones with pre-arranged contact lists. A simulator's address book cannot be filled from the command line without fragile database edits.
- Options considered: (a) Drive the Contacts app by UI automation: slow and brittle. (b) Edit the simulator's AddressBook SQLite file: undocumented schema. (c) In demo builds only, the app itself writes the signed-in persona's contact list into the simulator's Contacts through the public `CNContactStore` API, and removes the previous persona's seeded entries on sign-out.
- Chosen: (c). Any simulator can be any persona; switching is sign out and sign in with another test number. The seeding code is compiled only in `DEBUG` and runs only when `CONNECTCHA_DEMO=1` is in the environment.
- Reversibility: Easy; it is isolated in `DemoSeeder.swift`.

- **D-15: One hint line on the minimal profile** (2026-11-02, M4)
- Context: Spec 8.3 says the minimal profile shows only name and photo plus a Request button when eligible. Older relatives may not understand why a profile is empty.
- Options considered: (a) Strictly name, photo and button. (b) Add one short sentence ("Request to follow to see their posts and stories." or "Posts and stories are shared with people they approve.") that reveals nothing about the person.
- Chosen: (b). The sentence carries no content, counts or relationships.
- Reversibility: Trivial.

- **D-16: Settings and Edit profile built in M4 rather than M9** (2026-11-02, M4)
- Context: The demo and the UI tests need sign-out, and the profile tab needed an edit screen to be usable. Both were scheduled for M9.
- Chosen: Built now with the M9 scope (notification categories, support email, privacy and terms links, sign out, bio 150). M9 will revisit copy and polish only.
- Reversibility: n/a.

- **D-17: Videos play on demand behind a poster frame** (2026-11-02, M5)
- Context: Spec 2 wants fast loading on a normal phone connection. Autoplaying every video in the feed would download several megabytes while scrolling.
- Options considered: (a) Autoplay muted like Instagram: smooth, but costly on data and memory for older phones. (b) Show the 400 px thumbnail with a play button and duration; create the player when tapped. The MP4 has its moov atom first, so playback starts before the download finishes.
- Chosen: (b). It also keeps scrolling cheap and makes "what is a video" obvious to older relatives.
- Reversibility: Easy; `InlineVideoView` is the only place that decides.

- **D-18: "You're all caught up" position** (2026-11-02, M5)
- Context: Plan G7 stores the newest post seen when the person last left the feed. The spec doesn't say where the marker goes when nothing is new.
- Chosen: After the posts that are newer than that timestamp; at the very top when nothing is new; no marker on the first ever visit. The timestamp is sent when the feed disappears or the app goes to the background.
- Reversibility: Trivial; `FeedModel.caughtUpIndex` is unit-tested.

- **D-19: Media cache cleared on sign-out** (2026-11-02, M5)
- Context: An integration test showed the in-memory map of media id → signed URL surviving sign-out, so a second account on the same phone could reuse a URL the first account had fetched (until it expired).
- Chosen: `MediaCache.clearAll()` on every sign-out path, including the debug reset flag; disk URLCache is purged too.
- Reversibility: n/a (hygiene).

- **D-20: Location picker falls back to free text** (2026-11-02, M5)
- Context: MapKit search on a simulator or offline may return nothing; a relative may also want "Grandma's house".
- Chosen: The search sheet always offers "Use \"<typed text>\"" as the first row, storing the name without coordinates. Coordinates are stored only when a MapKit result is chosen.
- Reversibility: Trivial.
