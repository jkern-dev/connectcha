# Operations runbook

What's left to do, what exists today and how to run it. Written for the owner.

## What's left

Carried over on 2026-11-16 from the TestFlight plan and the owner's question list, both now in `archive/` (`archive/TESTFLIGHT_PLAN.md`, `archive/OPEN_QUESTIONS.md`). Everything else in those two files is done or settled.

**Where things stand (checked in App Store Connect, 2026-11-16):** build 0.1.0 (202611130829) has passed Beta App Review and is in testing. Two tester groups exist: "Family" (internal, 1 tester) and "beta test" (external, 2 testers, public link off).

### 1. Real-phone pass

These have never run on a simulator, so they must be seen working on phones:

- The Notification Service Extension: the saved-name swap on the lock screen. This is the product's signature privacy feature.
- Real push delivery end to end (outbox, webhook, function, APNs, phone).
- Real text messages through Twilio Verify, including the resend path and the non-US refusal (scenario 10).
- Real Contacts with limited access and `ContactAccessButton`.
- The camera path in the Snapshot creator, and the Messages composer for invites.
- Media timing on a cellular connection (Network Link Conditioner on the phone).

Walk `TEST_SCENARIOS.md` S1 to S17 on two phones running the TestFlight build. Expect a handful of real-device fixes.

### 2. Public invite link

1. In App Store Connect, enable the public link on the external group and set a tester limit (for example 50).
2. Paste the link into `web/index.html` (`TESTFLIGHT_LINK`) and push; Cloudflare Pages redeploys. Until then the invite page's join button says the link isn't live.

### 3. Before the link goes to more people

| Item | What to do |
|---|---|
| App icon | The build ships a placeholder (terracotta tile with a white "C", from `scripts/make-icon.swift`). Replace the three 1024 px PNGs (light, dark, tinted) in `ios/Connectcha/Resources/Assets.xcassets/AppIcon.appiconset`; no code changes. |
| Privacy policy and terms | `web/privacy.html` and `web/terms.html` are plain-language drafts, not legal advice. Have a lawyer or a reputable generator review them. |
| App Privacy in App Store Connect | Confirm it is filled in: contacts, phone number, photos and videos, user content; none used for tracking. |
| Reviewer test number | Rotate it now that Beta App Review has passed (see "Day-to-day" below). |
| Feed UI tests | Two failures on main as of 2026-11-12: the "Asked" button on the People tab, and the "Mom" saved name in the likes list. |

### 4. The first testers

- **Who:** 5 to 10 relatives and friends with US numbers and an iPhone. Seed the group so at least two people already have each other in Contacts; the first person in alone sees only the empty state.
- **How they install:** the invite page, nothing else. The acceptance test is a relative installing with no help.
- **What to watch in week one:** TestFlight crash reports and screenshot feedback; the support inbox; Supabase usage (database size, function invocations); Twilio balance; the `push_deliveries` table for failed sends.
- **What to ask testers:** did the lock-screen name read right, did they understand Snapshots and Letters without explanation, could they read it at their text size.
- **If Apple later objects to missing blocking or reporting** (spec 13.3, R4): build blocking first (hide each from the other, end follows, stop messages) and resubmit.

### Standing reminders

- A new build at least every 90 days; TestFlight builds expire.
- GitHub's macOS runners cost 10x minutes on a private repository. If minutes run low, restrict `.github/workflows/ios.yml` to manual runs.
- The safety work in `PRODUCT_SPEC.md` section 13.2 is due before the public App Store, 500 users, or strangers using the app, whichever comes first.

## What exists (local stack)

| Piece | Where | How to run |
|---|---|---|
| Postgres, Auth, Storage, Edge Functions | Supabase CLI in Docker | `make up`, `make down`, `make reset` |
| Access-rule tests (193 assertions) | `supabase/tests/*.sql` | `make test-db` |
| Edge Function tests | `supabase/functions/**/*_test.ts` | `make test-functions` |
| iOS unit and integration tests | `ios/ConnectchaTests` | `make ios-test` (stack must be up) |
| iOS scenario walkthroughs (UI tests) | `ios/ConnectchaUITests` | `make ios-ui-test` (resets data first) |
| Demo | `scripts/demo.sh`, `DEMO.md` | `make demo` |
| Push delivery to simulators | `scripts/push-bridge.sh` | started by `make demo`; `make push-bridge` to run alone |
| Privacy log check | `scripts/privacy-log-check.sh` | `make privacy-check` |
| Orphaned media cleanup | Edge Function `cleanup-orphans` | `curl -X POST http://127.0.0.1:54321/functions/v1/cleanup-orphans -H 'x-webhook-secret: local-dev-push-secret'` |
| CI | `.github/workflows/db-tests.yml` (pgTAP + Deno on Linux), `.github/workflows/ios.yml` (macOS runner) | on push |

### Secrets and configuration

- Local keys are the Supabase CLI defaults (`supabase status`). They are not secrets.
- Edge Function environment: `supabase/functions/.env` (gitignored), copied from `.env.example` by `make demo`. Holds the S3 endpoint and keys, the push webhook secret, and APNs settings.
- The database reads the webhook URL and secret from `private.settings` (seeded locally in `supabase/seed/00_test_helpers.sql`). A hosted project sets them once by SQL in the dashboard.
- The iOS app reads the API URL and anon key from `ios/Config/Local.xcconfig`.

### Logs and privacy

- Statement logging is `ddl` only, so parameters (hashes, captions, messages) never reach Postgres logs. `make privacy-check` verifies a submitted hash appears in no container log and no table.
- Edge Functions log counts and status codes only. `send-push` logs outbox id, type and device counts, never names or bodies.
- APNs payloads carry ids, a notification type and the sender's *profile* name; the message text is never included.

### Day-to-day

| Task | How |
|---|---|
| Put the demo back to its starting state | `make reset`, then relaunch simulators (`scripts/demo.sh as A josh`, `scripts/demo.sh as B ana`) |
| See the data | Studio at http://127.0.0.1:54323 (tables under `public`) |
| Add a demo person | Edit `supabase/seed/10_demo.sql` and `ios/Connectcha/Demo/DemoSeeder.swift`, add the number to `[auth.sms.test_otp]` in `supabase/config.toml` |
| Change the app name or bundle id | `ios/project.yml` (bundle ids, App Group), the two `.entitlements` files, `NotificationService.appGroup` |
| Answer an account-deletion email | People can delete themselves in Settings → Leaving (D-34). For someone who cannot sign in, in Studio or SQL: `delete from auth.users where phone = '1555…'`. Either way everything the person owns cascades, **including every conversation they were part of**, so their letters disappear from the other person's Letters too. Bucket objects go on the next `cleanup-orphans` run. |
| Rotate the reviewer account | Change the number or code in `[auth.sms.test_otp]` locally, or in the hosted Auth settings; nothing else references it |

## Hosted setup

The hosted project was set up this way in November 2026; the full account of that work is in `archive/TESTFLIGHT_PLAN.md` (phase C). The mechanics:

1. **Keys.** Copy `supabase/.hosted.env.example` to `supabase/.hosted.env` (gitignored) and fill it from the Supabase, Cloudflare and (later) Apple dashboards. Run `supabase login` once.
2. **`make hosted-setup`** (`scripts/hosted-setup.sh`, safe to rerun): links the CLI to the project, applies the migrations (seeds stay local), deploys the four Edge Functions, sets their secrets (R2 as the S3 endpoint, the webhook secret, APNs), writes the `private.settings` rows the push webhook reads, and schedules `cleanup-orphans` daily with `pg_cron`.
3. **Dashboard, Authentication (by hand, once).** Phone provider: Twilio Verify with the Account SID, Auth Token and Verify Service SID, and **"Enable phone confirmations" switched on** (off, GoTrue auto-confirms the phone, so `POST /auth/v1/signup` with a phone and password returns a session for any US number without a text; verified on the hosted project 2026-11-11). Twilio side: account upgraded with a balance, a Trust Hub Primary Compliance Profile created (without one Twilio refuses texts to unverified numbers, error 21608), Geo Permissions US only, Fraud Guard on. Test phone numbers: the reviewer number and its code only (Q8), written without the plus sign (`15555550100`, not `+1…`), or the lookup misses and the code goes to Twilio. Hooks: enable "Before User Created" pointing at `public.before_user_created_hook`, so non-US numbers are refused regardless of Twilio. Leave the SMS rate limits at their defaults.
4. **Never run `supabase config push`** (D-35). `supabase/config.toml` is the local stack: demo numbers with code 123456, a placeholder Twilio block, relaxed limits.
5. **App.** Put the project URL and anon key in `ios/Config/Hosted.xcconfig` (committed; the anon key is public by design). Release builds read it. For a Debug build on a phone against the hosted stack, `make ios-use-hosted`; `make ios-use-local` switches back.
6. **Cloudflare Pages.** Deploy `web/` (static, no build step). Put the Pages address in `Hosted.xcconfig` as `INVITE_URL`; the privacy and terms links in the app derive from it.
7. **GitHub Actions.** `make github-secrets` (`scripts/github-secrets.sh`, needs `gh auth login`) sets repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_DB_URL`, `BACKUP_PASSPHRASE` (generated once, kept in `supabase/.hosted.env`) and the repository variable `HOSTED_ENABLED=true`, then runs both workflows once. That turns on `keepalive.yml` (one read a day so the Free project never pauses) and `backup.yml` (weekly encrypted dump kept as a 90-day artifact).

### Push notifications for real

Needs the Apple Developer account: in Certificates, Identifiers & Profiles → Keys, create an APNs key and download the `.p8` (shown once). Put `APNS_MODE=apns`, the Key ID, the Team ID and the key's contents (line breaks as `\n`) in `supabase/.hosted.env` and rerun `make hosted-setup`. Tokens from Debug builds are sent to the sandbox APNs server and tokens from TestFlight builds to production, chosen per token (D-33); nothing to switch.

### Shipping a build (every 90 days at the latest)

1. Copy `.apple.env.example` to `.apple.env` (gitignored): Team ID, and an App Store Connect API key (Users and Access → Integrations) with its Key ID, Issuer ID and `.p8` path.
2. `make archive`: a Release build for real iPhones with the build number set to the current date and time, so every upload is unique and increasing. The version itself is `MARKETING_VERSION` in `ios/project.yml`.
3. `make upload`: exports with `ios/ExportOptions.plist` and uploads. Signing is manual: the API key's App Manager role cannot use Apple's cloud signing, so the Apple Distribution certificate (private key `~/Projects/connectcha-keys/dist.key`, in the login keychain) and the two App Store profiles ("Connectcha App Store", "Connectcha NSE App Store", in `~/Library/Developer/Xcode/UserData/Provisioning Profiles`) were created through the App Store Connect API on 2026-11-12 and expire 2027-11-12; recreate them the same way when they do. The archive step still signs with the development profiles (automatic) and needs at least one registered device. The app is iPhone-only (`TARGETED_DEVICE_FAMILY` 1 on both targets); App Store validation otherwise demands all four iPad orientations. The build appears in App Store Connect → TestFlight after processing (10 to 30 minutes), first for the internal group, then for external testers once Beta App Review approves it (the first build of a version is reviewed; later builds usually are not).
4. The first time only: in App Store Connect, create the app record, fill App Privacy, Test Information and Beta App Review information (`archive/TESTFLIGHT_PLAN.md` phase E; done for 0.1.0 except the public link, see "What's left"), and after approval enable the public link, set a tester limit, paste the link into `web/index.html` (`TESTFLIGHT_LINK`) and redeploy Pages.

### Restoring a backup

Download the artifact from the Actions run, then:

```sh
gpg --decrypt connectcha-YYYY-MM-DD.tar.gz.gpg > dump.tar.gz   # asks for BACKUP_PASSPHRASE
tar xzf dump.tar.gz
psql "$SUPABASE_DB_URL" -f dump/schema.sql
psql "$SUPABASE_DB_URL" -f dump/data.sql
```

Media lives in R2, which keeps the objects; the dump restores the rows that point at them.

### Upgrade triggers

Move to Supabase Pro (25 USD/month) when the database nears 500 MB, when automatic backups and no pausing are worth it, or when more than a few dozen people are active. Top up Twilio when the balance nears 5 USD.
