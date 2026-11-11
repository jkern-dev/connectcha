# Operations runbook

What exists today, how to run it, and what M10 (TestFlight) adds. Written for the owner.

## What exists now (local prototype)

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

Order and detail are in `TESTFLIGHT_PLAN.md` (phase C). The mechanics:

1. **Keys.** Copy `supabase/.hosted.env.example` to `supabase/.hosted.env` (gitignored) and fill it from the Supabase, Cloudflare and (later) Apple dashboards. Run `supabase login` once.
2. **`make hosted-setup`** (`scripts/hosted-setup.sh`, safe to rerun): links the CLI to the project, applies the migrations (seeds stay local), deploys the four Edge Functions, sets their secrets (R2 as the S3 endpoint, the webhook secret, APNs), writes the `private.settings` rows the push webhook reads, and schedules `cleanup-orphans` daily with `pg_cron`.
3. **Dashboard, Authentication (by hand, once).** Phone provider: Twilio Verify with the Account SID, Auth Token and Verify Service SID, and **"Enable phone confirmations" switched on** (off, GoTrue auto-confirms the phone, so `POST /auth/v1/signup` with a phone and password returns a session for any US number without a text; verified on the hosted project 2026-11-11). Twilio side: Geo Permissions US only, Fraud Guard on. Test phone numbers: the reviewer number and its code only (Q8), written without the plus sign (`15555550100`, not `+1…`), or the lookup misses and the code goes to Twilio. Hooks: enable "Before User Created" pointing at `public.before_user_created_hook`, so non-US numbers are refused regardless of Twilio. Leave the SMS rate limits at their defaults.
4. **Never run `supabase config push`** (D-35). `supabase/config.toml` is the local stack: demo numbers with code 123456, a placeholder Twilio block, relaxed limits.
5. **App.** Put the project URL and anon key in `ios/Config/Hosted.xcconfig` (committed; the anon key is public by design). Release builds read it. For a Debug build on a phone against the hosted stack, `make ios-use-hosted`; `make ios-use-local` switches back.
6. **Cloudflare Pages.** Deploy `web/` (static, no build step). Put the Pages address in `Hosted.xcconfig` as `INVITE_URL`; the privacy and terms links in the app derive from it.
7. **GitHub Actions.** Repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_DB_URL`, `BACKUP_PASSPHRASE`; repository variable `HOSTED_ENABLED=true`. That turns on `keepalive.yml` (one read a day so the Free project never pauses) and `backup.yml` (weekly encrypted dump kept as a 90-day artifact).

### Push notifications for real

Needs the Apple Developer account: in Certificates, Identifiers & Profiles → Keys, create an APNs key and download the `.p8` (shown once). Put `APNS_MODE=apns`, the Key ID, the Team ID and the key's contents (line breaks as `\n`) in `supabase/.hosted.env` and rerun `make hosted-setup`. Tokens from Debug builds are sent to the sandbox APNs server and tokens from TestFlight builds to production, chosen per token (D-33); nothing to switch.

### Shipping a build (every 90 days at the latest)

1. Copy `.apple.env.example` to `.apple.env` (gitignored): Team ID, and an App Store Connect API key (Users and Access → Integrations) with its Key ID, Issuer ID and `.p8` path.
2. `make archive`: a Release build for real iPhones with the build number set to the current date and time, so every upload is unique and increasing. The version itself is `MARKETING_VERSION` in `ios/project.yml`.
3. `make upload`: exports with `ios/ExportOptions.plist` and uploads. The build appears in App Store Connect → TestFlight after processing (10 to 30 minutes), first for the internal group, then for external testers once Beta App Review approves it (the first build of a version is reviewed; later builds usually are not).
4. The first time only: in App Store Connect, create the app record, fill App Privacy, Test Information and Beta App Review information (`TESTFLIGHT_PLAN.md` phase E), and after approval enable the public link, set a tester limit, paste the link into `web/index.html` (`TESTFLIGHT_LINK`) and redeploy Pages.

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
