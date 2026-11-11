# From prototype to TestFlight (M10)

Written 2026-11-06 for the owner. What stands between the current prototype (M0 to M9 built, restyled, all suites green, everything running on one Mac) and a build that 5 to 10 relatives can install from a link and use with real phones, real texts and real notifications.

Companion files: `OPERATIONS.md` (runbook), `OPEN_QUESTIONS.md` (Q1 to Q10), `IMPLEMENTATION_PLAN.md` section 6 (owner items O1 to O10) and M10.

## Where things stand

- The app, database, server functions, tests and demo are complete for the scope in the plan. Nothing has ever run outside this Mac: no hosted server, no real text message, no real notification, no real phone.
- An unsigned Release build for a physical iPhone compiles (checked 2026-11-06), so the release configuration is not hiding build errors.
- Every "local only" convenience is behind `DEBUG`, so a release build carries none of the demo switches.

## The critical path

Items only the owner can do come first because everything else waits on them. Rough calendar: about two weeks, most of it waiting on Apple and on real-phone findings.

```
Owner: Apple enrolment ─┐
Owner: name, email, icon, legal ─┼─► Hosted stack ─► Dev build on the owner's iPhone ─► fixes ─► Archive ─► Internal TestFlight ─► Beta App Review ─► Public link ─► Invite testers
Owner: Supabase, Twilio, Cloudflare ─┘
```

## Phase A: Owner tasks (accounts and decisions)

| # | Task | Why it blocks | Notes |
|---|---|---|---|
| A1 | **Apple Developer Program**, Individual, 99 USD/year. Confirm the enrolment has gone through. | Signing a build for a real phone, push notifications, App Store Connect and TestFlight all need it. Nothing in phases D and E starts without it. | Applied; awaiting Apple's confirmation as of 2026-11-06. |
| A2 | **Final name and bundle identifier** (Q1). | The bundle ID cannot change once an App Store Connect record exists. A name change later means a new record. | Settled 2026-11-06: the name is Connectcha; the bundle ID stays `com.connectcha.app` (extension `com.connectcha.app.nse`, App Group `group.com.connectcha.shared`). The App Store name itself is checked by Apple when the record is created (phase E). |
| A3 | **Support email** (Q2). | Appears in Settings, the invite page, the legal pages and the TestFlight feedback field. | Settled 2026-11-06: `ask.connectcha@gmail.com` (spelling to be confirmed by the owner before it goes into the build). |
| A4 | **Privacy policy and terms** (Q3). Have the drafts in `web/` reviewed by a lawyer or a reputable generator. | TestFlight's Test Information requires a privacy policy URL before external testing. | The drafts already cover the points the plan lists; review is for wording and completeness. |
| A5 | **Hosted accounts**: Supabase (Free), Twilio (upgrade from trial, about 20 USD prepaid, Verify service, Geo Permissions US only, Fraud Guard), Cloudflare (R2 bucket `connectcha-media`, R2 API token, Pages). | Real phones need a reachable server, real sign-ups need real texts, media needs a bucket. | Accounts created as of 2026-11-06; configuration happens in phase C, one service at a time. Each sign-in text costs about 0.06 USD. |
| A6 | **App icon artwork** (Q9). Three 1024 px PNGs (light, dark, tinted). | Not a hard blocker; TestFlight accepts the placeholder tile. | Replace the files in `AppIcon.appiconset`; no code change. |
| A7 | **Reviewer test account** (Q8). Choose a number and six-digit code that will exist only in the hosted Auth settings. | Beta App Review signs in with it. | Rotate it after review. |
| A8 | **Decide on in-app account deletion** (spec 13.2 deferred it; see B3). | Apple guideline 5.1.1(v) requires it for apps with account creation, and Beta App Review sometimes enforces it. | Recommendation: build it now. It is about half a day and removes the most likely review rejection. |

## Phase B: Code changes (the build agent)

| # | Change | Why | Size |
|---|---|---|---|
| B1 | **Hosted build configuration.** Add `ios/Config/Hosted.xcconfig` (hosted Supabase URL and anon key, `INVITE_URL` on Pages, real `SUPPORT_EMAIL`) and point the Release config at it in `project.yml`; Debug keeps `Local.xcconfig`. | Today both Debug and Release read `Local.xcconfig`, so an archive would talk to 127.0.0.1. | Small |
| B2 | **Build numbers.** Set `CURRENT_PROJECT_VERSION` from a `make archive` target (date-based or counter) instead of the hard-coded `CFBundleVersion: "1"`. | App Store Connect rejects a second upload with the same build number. | Small |
| B3 | **In-app account deletion** (if A8 says yes). One `delete_my_account` RPC that deletes the `auth.users` row (everything the person owns cascades; their sent messages stay, like email) plus a confirmed button in Settings. pgTAP test and a UI test. | See A8. | Half a day |
| B4 | **Sandbox vs production push tokens.** A build from Xcode on a phone gets a *sandbox* APNs token; a TestFlight build gets a *production* one, and the two APNs servers reject each other's tokens. Register the platform as `ios_sandbox` in DEBUG builds and let `send-push` pick the host per token. Today `platform` is `ios` or `ios_simulator` and the host is one global setting. | Without it, either the owner's dev phone or every tester gets no pushes. | Small (migration check constraint, `NotificationManager`, `send-push`, Deno test) |
| B5 | **Hosted-safe Supabase config.** `supabase config push` would carry `sms_sent = 1000`, `max_frequency = "1s"`, the nine demo test numbers and the placeholder Twilio block to the hosted project. Either keep hosted Auth settings in the dashboard only, or split the local-only values so a push is safe. | Demo numbers with code 123456 must not exist on the real server. | Small |
| B6 | **Web pages.** Fill `TESTFLIGHT_LINK` in `web/index.html` once the public link exists; replace the support address in the three HTML files; deploy to Cloudflare Pages. | The invite page is how relatives install. | Small |
| B7 | **Operations jobs.** GitHub Actions cron: daily keep-alive read (Supabase Free pauses after a week idle) and weekly `pg_dump` to a private location; Supabase cron calling `cleanup-orphans` daily. | Plan M10 scope. Can follow the first build. | Half a day |
| B8 | **`make archive` and `make upload`** targets (xcodebuild archive, export with the App Store method, upload with `altool`/`xcrun notarytool` equivalent for iOS: `xcodebuild -exportArchive` then App Store Connect API key). | Repeatable 90-day rebuilds without clicking through Xcode. Optional for the first build, which can be done from Xcode's Organizer. | Small |

## Phase C: Hosted environment bring-up

Done by the build agent with the owner's credentials, following `OPERATIONS.md`:

1. `supabase link`, `supabase db push` (migrations only; seeds stay local), `supabase functions deploy`.
2. Dashboard: enable the `before_user_created` hook; Phone provider = Twilio Verify with the Service SID; add the reviewer test number (A7); confirm the default SMS rate limits.
3. Function secrets: `S3_*` for R2, `PUSH_WEBHOOK_SECRET`, `APNS_MODE=apns`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`. Set `private.settings` rows `push_webhook_url` and `push_webhook_secret` by SQL.
4. Smoke test from the Mac: sign up with the owner's real number through the hosted API, upload a photo, confirm it lands in R2.
5. Run `scripts/privacy-log-check.sh` logic against the hosted logs once (plan 5, "before launch").

## Phase D: First runs on real iPhones

This is where the unknowns are. Nothing below has ever executed:

- The Notification Service Extension (simulators never run it). The saved-name swap on the lock screen is the product's signature privacy feature; it must be seen working on a phone.
- Real APNs delivery end to end (outbox, webhook, function, APNs, phone).
- Real text messages through Twilio Verify, including the resend path and the non-US refusal (scenario 10).
- Real Contacts with iOS 18 limited access and `ContactAccessButton`.
- The camera path in the story creator and the Messages composer for invites.
- Media timing on a cellular connection (plan M5 acceptance; use Network Link Conditioner on the phone).

Steps: register the two bundle IDs and the App Group under the team in Xcode (automatic signing does this), run a Debug build on the owner's iPhone pointed at the hosted stack, then a second phone (a relative's or a spare). Walk `TEST_SCENARIOS.md` S1 to S17 on the two phones. Expect to find and fix a handful of real-device issues; budget two to three days including fixes.

## Phase E: App Store Connect and TestFlight

1. Create the app record (name, bundle ID, primary language, SKU). Create the APNs key (.p8) and hand it to phase C step 3.
2. Fill App Privacy (contacts, phone number, photos and videos, user content; none used for tracking). Not strictly required for TestFlight but ten minutes now avoids a surprise later.
3. Archive (Release, `Hosted.xcconfig`) from Xcode on this Mac and upload. Xcode Cloud can come later; for one person shipping every 90 days, the Organizer is simpler.
4. **Internal testing** group with the owner's own devices: no review, available within minutes. Repeat the scenario walk on the TestFlight build (production APNs now).
5. **External testing**: Test Information (beta description in plain words, feedback email from A3, privacy URL from A4) and Beta App Review information (contact details; sign-in required; the reviewer number and code; notes that discovery is contacts-only, that the reviewer's second test account is already in the first one's contacts, and that non-US numbers are refused by design). Submit. Expect one to two days.
6. If review objects to missing blocking or reporting (spec R4), build blocking first (one to two days: hide each from the other, end follows, stop messages) and resubmit. Do not pre-build it for 5 to 10 known people.
7. After approval: enable the public link, set a tester limit (for example 50 for this round), paste it into `web/index.html` (B6), deploy Pages.

## Phase F: Testing with actual users

- **Who:** 5 to 10 relatives and friends with US numbers and an iPhone on iOS 18 or later. Seed the group so at least two people already have each other in Contacts; the first person in alone sees only the empty state.
- **How they install:** the invite page, nothing else. Plan M10's acceptance test is a relative installing with no help.
- **What to watch in week one:** TestFlight crash reports in App Store Connect; TestFlight screenshot feedback and the support inbox; Supabase usage (database size, function invocations); Twilio balance; the `push_deliveries` table for failed sends.
- **What to ask testers:** the three things the design was built for: did the lock-screen name read right, did they understand Snapshots and Letters without explanation, could they read it at their text size.
- **Routine:** a new build at least every 90 days (builds expire); answer deletion emails per `OPERATIONS.md` until B3 ships; move to Supabase Pro when the database nears 500 MB or backups matter.

## Not needed for this round

- Blocking, reporting, moderation, age checks, CSAM scanning (spec 13.2): required before public launch or 500 users, not for a closed group of known people. R4 covers the review risk.
- Xcode Cloud, a custom domain, rewriting git history to drop the 170 MB build folder in commit `df36598`.
- Replacing the placeholder icon before the internal build (do it before the public link).

## Implementation plan: code first, then the hosted services

Agreed 2026-11-06: do the code changes before configuring Supabase, Twilio and Cloudflare, so that when the services are set up the app and the deployment scripts are ready to point at them. None of the steps below needs the Apple account; the two that need it to be *verified* (steps 6 and 7) are written now and exercised later.

### Step 1. Hosted build configuration (B1)

- Add `ios/Config/Hosted.xcconfig`, committed: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (public by design; it ships inside the app), `INVITE_URL` (the Pages address), `SUPPORT_EMAIL`. Values are placeholders until phase C fills them.
- Add `ios/Config/Debug.xcconfig`: includes `Local.xcconfig`, then optionally includes a gitignored `Override.xcconfig`. `make ios-use-hosted` writes an override that includes `Hosted.xcconfig`; `make ios-use-local` removes it. That is how a Debug build on the owner's iPhone talks to the hosted stack (phase D) without touching the committed files.
- `project.yml`: Debug reads `Debug.xcconfig`, Release reads `Hosted.xcconfig`.
- Put the real support email in `Local.xcconfig`, `scripts/write-ios-config.sh`, the `AppConfig` fallback and the three files under `web/`.
- Check: a Release build still compiles; a Debug build with the override reports the hosted URL in its Info.plist.

### Step 2. Versions and build numbers (B2)

- `project.yml`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` as project-level settings so the app and the extension always match (Apple rejects a mismatch); both Info.plists read `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`.
- `make archive` passes a date-based build number (`YYYYMMDDHHMM`), which is always increasing and needs no counter file.
- Check: `make ios-build` still works; the generated plists carry the variables.

### Step 3. Sandbox and production push tokens (B4)

- New migration `20261106000100_push_platforms.sql`: the `device_tokens.platform` check gains `ios_sandbox`.
- `NotificationManager.didRegister` registers `ios_sandbox` in DEBUG builds (Xcode installs a development push entitlement) and `ios` otherwise (TestFlight and App Store builds get production).
- `send-push`: choose the APNs host per token (`ios` production, `ios_sandbox` sandbox); the `APNS_ENVIRONMENT` setting goes away. `apnsHost(platform)` is a pure function with a Deno test. Simulator tokens are still skipped in `apns` mode.
- Checks: pgTAP accepts the new platform; Deno tests pass; `make ios-test`.

### Step 4. In-app account deletion (B3, recommended)

- What happens today if a user row is deleted: everything cascades, including **whole conversations**, so letters the person wrote *and received* vanish from the other person's Letters too. `OPERATIONS.md` claims sent messages remain; that is wrong and will be corrected.
- Decision for the owner (default chosen if no objection): keep the cascade. The account and everything about it is gone, including conversations with them, like a person leaving a group. Keeping their letters would need a "deleted person" placeholder in the schema and the UI; not worth it for this round.
- Server: `delete_my_account()` as a `SECURITY DEFINER` function deleting the caller's `auth.users` row. Bucket objects become orphans and `cleanup-orphans` removes them on its daily run. pgTAP test: the user's rows are gone, the other party's own posts and follows are untouched, the shared conversation is gone.
- App: Settings gains a "Delete your account" row under Help with a confirmation that says in plain words what disappears, then clears the local session, the match map and the media cache the same way sign-out does. `OPERATIONS.md` keeps the by-email path for people who cannot sign in.
- Checks: pgTAP; a UI test in `SettingsUITests` (new class, added to `UI_TEST_CLASSES`) that deletes the seeded fresh user and lands on sign-in.

### Step 5. Hosted-safe Supabase configuration (B5)

- `supabase/config.toml` stays the local file. Add a comment block at the top and a line in `OPERATIONS.md`: never run `supabase config push`; hosted Auth settings (Twilio Verify, test numbers, rate limits, the hook) are set in the dashboard in phase C. This avoids shipping the demo numbers with code 123456 to the real server.
- `scripts/hosted-setup.sh`: the phase C commands in order (`supabase link`, `db push`, `functions deploy`, secrets, the two `private.settings` rows), each idempotent, reading values from a gitignored `supabase/.hosted.env`. Written now, run in phase C.

### Step 6. Archive and upload targets (B8; verified after Apple approves)

- `ios/ExportOptions.plist` (App Store Connect method, automatic signing, `DEVELOPMENT_TEAM` from the environment).
- `make archive` (Release, `generic/platform=iOS`, build number from step 2) and `make upload` (`xcodebuild -exportArchive` with an App Store Connect API key from the environment). Documented in `OPERATIONS.md` as the 90-day routine.

### Step 7. Operations jobs (B7; enabled after phase C)

- `.github/workflows/keepalive.yml`: daily, one authenticated read against the hosted REST endpoint so the Free project never pauses.
- `.github/workflows/backup.yml`: weekly `supabase db dump` of data and schema, encrypted with a repository secret before being stored as a workflow artifact (90-day retention, private repository). Restoring is documented in `OPERATIONS.md`.
- The daily `cleanup-orphans` schedule is SQL (`pg_cron` plus `pg_net`) in `scripts/hosted-setup.sh`, not a migration, so local resets are unaffected.

### Step 8. Documentation

- `OPERATIONS.md`: hosted section rewritten around `scripts/hosted-setup.sh`, the deletion correction, the archive routine, the backup restore.
- `DECISIONS.md`: D-33 (push platforms), D-34 (account deletion cascade), D-35 (config.toml is local only).
- `OPEN_QUESTIONS.md`: Q1, Q2, Q8 marked settled.

Order: 1, 2, 3, 5 first (configuration, about half a day), then 4, then 6, 7, 8. Then phase C, one service at a time: Supabase, Cloudflare R2 and Pages, Twilio.

**Status 2026-11-06:** steps 1 to 8 are implemented (see D-33 to D-35 and the "Hosted setup" and "Shipping a build" sections of `OPERATIONS.md`). The owner settled the deletion question: everything goes, conversations included. Steps 6 and 7 are written but can only be exercised once the Apple account and the hosted services exist.

**Phase C progress (2026-11-06):**
- **Supabase: done.** Project `lmsdnuouvgqsryvhoxzx` (us-west-2) linked; all seven migrations applied (18 tables, all with row-level security; 53 client-callable functions; the US-only hook function present); the four Edge Functions deployed and answering (send-push refuses calls without the secret, get-media-urls refuses calls without a session); `private.settings` holds the webhook URL and secret; `cleanup-orphans` scheduled daily at 09:00 UTC with `pg_cron`. `ios/Config/Hosted.xcconfig` carries the project URL and publishable key. `supabase/.hosted.env` (gitignored) holds the project reference, database password and webhook secret.
- **Still in the Supabase dashboard, at the Twilio step:** Phone provider (Twilio Verify), the reviewer test number, and switching on the "Before User Created" hook (Authentication → Hooks → Postgres function `public.before_user_created_hook`).
- **Cloudflare R2: done (2026-11-11).** Bucket `connectcha-media` with a read-and-write token scoped to it; `R2_*` filled in `supabase/.hosted.env` and `make hosted-setup` rerun (the owner runs it; the S3 secrets are on the functions). Verified: hosted `cleanup-orphans` lists the bucket (scanned 0), and a presigned PUT, presigned GET, runtime list and delete all succeeded against R2 through `_shared/s3.ts`.
- **Cloudflare Pages: done (2026-11-11).** Project `connectcha` connected to the GitHub repo (`main`, output directory `web`), so pushes redeploy. Production address `https://connectcha.pages.dev/` matches `INVITE_URL`; `privacy.html` and `terms.html` answer (Pages redirects them to the extensionless paths, which the app's links follow). `TESTFLIGHT_LINK` in `web/index.html` still waits for the public TestFlight link (phase E).
- **Twilio: done (2026-11-11), except the real-number text.** Verify service created; Supabase Phone provider on Twilio Verify with "Enable phone confirmations" ON; "Before User Created" hook on; reviewer test number `15555550100` / `123456` (no plus sign in the dashboard entry). Verified from outside: UK number refused before any text; password sign-up without a verified phone refused (it issued a session while confirmations were off, now fixed, OPERATIONS.md step 3); the reviewer number signs in with the fixed code and no text. Still to do: one sign-in with a real US number to see a Twilio text arrive, then the GitHub secrets (step 7).

### What phase C will need from each account

Gather these while the code work happens; paste keys into `supabase/.hosted.env` (gitignored), not into chat.

| Service | What | Where to find it |
|---|---|---|
| Supabase | Project reference (the `xxxx.supabase.co` part), publishable (anon) key, database password, and a one-time `supabase login` in the terminal | Project Settings → General and API Keys; the password was set when the project was created |
| Cloudflare R2 | Account ID, bucket name, an API token with object read and write on that bucket (access key ID and secret) | R2 → Overview (account ID), bucket page, Manage R2 API Tokens |
| Cloudflare Pages | The project's `*.pages.dev` address (or custom domain) | Pages → the project |
| Twilio | Account SID, Auth Token, the Verify Service SID; Geo Permissions set to US only | Console home (SID and token), Verify → Services |
| Apple (later) | Team ID, an APNs key `.p8` with its Key ID, an App Store Connect API key for uploads | Developer account → Membership; Certificates, Identifiers & Profiles → Keys; App Store Connect → Users and Access → Integrations |
