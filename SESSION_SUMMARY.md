# Build session summary (2026-10-31 to 2026-11-02)

For the owner. What was built, what was not and why, decisions worth knowing, known issues, and what to do first next time. Companion files: `DEMO.md` (run it), `TEST_SCENARIOS.md` (proof), `DECISIONS.md` (choices), `OPEN_QUESTIONS.md` (yours to settle), `OPERATIONS.md` (runbook), `REFINEMENT_LOG.md` (polish passes).

## What was built

Milestones M0 to M9 of `IMPLEMENTATION_PLAN.md`, running entirely on this Mac:

- **Backend (Supabase, local Docker).** The full schema, row-level security on every table, 50 server functions (writes as `SECURITY DEFINER` RPCs, reads as JSON read models), the US-only sign-up hook, the push outbox with a `pg_net` webhook, and four Edge Functions: `create-upload-urls`, `get-media-urls` (presigned S3 URLs, filtered by RLS), `send-push` (settings, tokens, APNs client with a stub mode) and `cleanup-orphans`.
- **iOS app (Swift 6, SwiftUI, iOS 18+).** Sign-in by fixed-code text numbers; seven-step onboarding in the spec's order; contacts matching with on-device hashing and a match map in the App Group; People tab with per-person requests, invites and the non-US message; follow requests, approvals, follow-back prompt, unfollow, remove follower, private follower and following lists; feed with posts of 1 to 10 photos and videos, likes, poster-only likers, edit and delete, "You're all caught up", empty state; stories with tray, viewer, reactions and replies, text overlay, archive, save to Photos; private responses and conversations with realtime and the read-only state; activity list with grouped likes; notifications with deep links; settings; Dynamic Type up to the largest accessibility size; light and dark mode.
- **Demo.** `make demo` starts everything and launches two simulators signed in as Josh and Ana, with seven seeded people, photos, videos, stories, conversations and pending requests. A bridge delivers notification banners to the simulators.
- **Tests.** 193 pgTAP assertions covering every row of plan 3.6; 11 Deno tests; iOS unit and integration tests (phone normalising, matching with a recorded-wire proof that no contact name leaves the device, media and post pipelines, feed marker, story compositing, push rewriting); UI tests for all 17 scenarios plus onboarding and notifications.
- **Web.** The invite page with iPhone and Android branches, and draft privacy and terms pages.

## What was not built, and why

- **M10 (TestFlight)** was out of scope for this session. `OPERATIONS.md` lists what it needs.
- **Real APNs delivery** needs the Apple Developer account. The path is complete up to the APNs call; `APNS_MODE=stub` plus the bridge stands in on simulators. The simulator does not run Notification Service Extensions, so the extension itself has not executed yet; its logic is unit-tested and the bridge applies the same rewrite.
- **Hosted services** (Supabase project, Twilio, R2, Pages) were not created, per the brief. Switching is configuration (`OPERATIONS.md`).
- **Throttled-network timing** (plan M5 acceptance with Network Link Conditioner) was not measured; simulators have no throttle. Thumbnails are 400 px JPEGs of 10 to 20 KB and videos have the moov atom first, so the design meets the goal, but the numbers need a phone.
- **Nothing from spec sections 12 or 13** was built, as instructed. `IMPLEMENTATION_PLAN.md` section 9 still describes where each item slots in.

## Decisions you should know about

Full list in `DECISIONS.md`. The ones that change what you will see or pay:

1. **Profiles are not a directory** (D-05). You can only read someone's name by holding a relationship with them or their number. Stricter than the plan.
2. **Non-US numbers are refused by the database** (D-03), not only by Twilio.
3. **No PhoneNumberKit** (D-02); a small US-only normaliser instead.
4. **Avatars are media rows** (D-06), one upload path for everything.
5. **Settings and Edit profile were built early** (D-16) because the demo needed sign-out.
6. **Pushes never contain message text** (D-29): "Mom responded to your post", not the words.
7. **Debug-only switches** (D-11) make the demo possible: auto sign-in by test number, start tab, contact seeding, in-app push poller. None exist in release builds.
8. **Layouts stack at large text sizes** instead of shrinking text (D-30).

## Known issues

- Emoji render as a missing-glyph box in the iOS 26.3 simulator runtime on this Mac. The bytes are correct; phones render them.
- The GitHub macOS runner workflow was failing on the runner's Xcode/simulator pairing; a fix was pushed at the end of the session and should be checked on the next push.
- Running the UI suites changes data (follows, requests, conversations); `make reset` or `make demo` restores the demo state. `make ios-ui-test` resets first.
- The share sheet stands in for Messages on simulators (no Messages app there).
- Camera is unavailable on simulators; the story creator says so and offers the camera roll.

## Recommended first steps next session

1. Run `make demo` and walk `DEMO.md` end to end; note anything confusing in `REFINEMENT_LOG.md`.
2. Settle `OPEN_QUESTIONS.md` Q1 (name) and Q2 (support email); both are one-line changes.
3. Enrol in the Apple Developer Program (Q4), then run the app on a real iPhone: that exercises the Notification Service Extension, Messages invites, the camera and real contacts.
4. Create the hosted Supabase project and R2 bucket (`OPERATIONS.md`), point the app at them, and test with two real phones.
