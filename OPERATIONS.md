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
| Answer an account-deletion email | Not automated yet. In Studio (or SQL): `delete from auth.users where phone = '1555…'`; every row the person owns cascades. Messages they sent to others remain (spec 13.2 leaves this decision to the owner). |
| Rotate the reviewer account | Change the number or code in `[auth.sms.test_otp]` locally, or in the hosted Auth settings; nothing else references it |

## What changes for hosted (end of M5 in the plan, before M10)

1. **Supabase project (Free).** `supabase link`, `supabase db push` (migrations only; seeds stay local), `supabase functions deploy`. Set `private.settings` rows `push_webhook_url` (`https://<ref>.supabase.co/functions/v1/send-push`) and `push_webhook_secret`. Set function secrets: `S3_*`, `PUSH_WEBHOOK_SECRET`, `APNS_*`.
2. **Twilio Verify.** Provider Twilio Verify in Auth settings; Geo Permissions US only; keep the `before_user_created` hook (it is in the migrations) so non-US numbers are refused regardless.
3. **Cloudflare R2.** Private bucket; set `S3_ENDPOINT=https://<account>.r2.cloudflarestorage.com`, `S3_BUCKET`, `S3_REGION=auto`, the token's key pair. No code changes; the functions presign the same way.
4. **Reviewer and test numbers.** Hosted Auth → Phone → test OTPs: one reviewer number with a fixed code. Remove the demo numbers.
5. **Cron.** Schedule `cleanup-orphans` daily (Supabase cron calling the function with the secret header).

## What M10 adds (TestFlight)

- Apple Developer Program (individual), bundle id and App Group registered, APNs key (.p8) → `APNS_MODE=apns`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`.
- App Store Connect record, `ITSAppUsesNonExemptEncryption = NO` (already in `Info.plist`), beta description, feedback email, privacy policy URL, review notes (contacts-only model, two test accounts).
- Public TestFlight link pasted into `web/index.html` (`TESTFLIGHT_LINK`), site deployed to Cloudflare Pages, support email replaced in `ios/Config/Local.xcconfig` (`SUPPORT_EMAIL`) and the web pages.
- Keep-alive Worker (daily read) while on the Free plan; weekly `pg_dump` from GitHub Actions to a private location.
- 90-day rebuild cadence: builds expire; ship a new build at least every 90 days.
- Move to Supabase Pro when the database nears 500 MB or you want backups and no pausing.
