# Connectcha: Implementation Plan

**Status:** Ready to build. No application code exists yet.
**Date:** 2026-10-31
**Source of truth for behaviour:** `PRODUCT_SPEC.md` (revised 2026-10-31). Where this plan and the spec disagree, the spec wins and this plan has a bug.
**Audience:** the coding agent that will build the app, and the product owner who will run the accounts and the TestFlight release.

This plan is self-contained. The build agent should not need the conversation that produced it.

---

## 1. Summary

### 1.1 What will be built

A native iOS app, a Postgres backend with row-level access rules, a small set of server functions, and a one-page invite website, implementing the first version of Connectcha as defined in `PRODUCT_SPEC.md`:

- Phone-number sign-up by text code, US numbers only, with first and last name and an optional photo.
- Discovery only through the phone's contacts, matched on-device-derived hashes and never stored on the server.
- One-way private following with approval for every follow, including follow-backs.
- Newest-first feed of photo and video posts (1 to 10 items, video up to 60 seconds), likes, and private responses to posts that open a one-to-one conversation.
- 24-hour stories with a tray, viewer, text overlays, location tag, private archive and "save to phone".
- Messaging limited to responses and follow-ups, allowed only while at least one person follows the other.
- Push notifications for requests, approvals and messages; per-person "Notify me" bells for posts and stories.
- Distribution by public TestFlight link, and an invite web page with iPhone instructions and an Android "Coming soon".

Everything in spec section 12 (out of scope) and section 13 (deferred until public launch) is **not** built now. Section 9 of this plan shows where the design leaves room for the section 13 work.

### 1.2 Changes to the spec agreed during review

These were agreed with the owner on 2026-10-31 and have been written into `PRODUCT_SPEC.md`:

| # | Change | Spec sections | Reason |
|---|---|---|---|
| C1 | **"Request all" is replaced by a checklist with nothing preselected and a single "Send requests" button.** No select-all control anywhere. | 9.1 step 5, 8.5 | Apple's App Store Review Guideline 5.1.2(v) forbids contacting people using Contacts data except "at the explicit initiative of that user on an individualized basis" and says "do not include a Select All option or default the selection of all contacts". Follow requests trigger a push to the recipient, so a reviewer could treat "Request all" as exactly that. The guideline text was checked on 2026-10-31. |
| C2 | **The "mutual followers" hint on follow requests is removed.** Requests show name, photo and the contacts label only. | 3.4 | It revealed part of another person's follower and following lists, which 8.4 and principle 6 forbid without exception. The owner chose strict privacy. |
| C3 | **Section 14 defaults A1 to A7 are confirmed.** A6 limits: caption 1,000 characters, bio 150, message 2,000. | 14 | Owner confirmation. |

### 1.3 Interpretations of gaps (no spec change needed)

Decisions the build agent should follow where the spec is silent. Each follows the product principles.

| # | Gap | Decision |
|---|---|---|
| G1 | Saved contact names in **push notifications** (spec 3.2 says saved names apply "everywhere in the app", but the server never knows them). | The server sends the sender's profile name plus the sender's user ID in the push payload with `mutable-content: 1`. A Notification Service Extension on the device swaps in the saved contact name when the sender is in the local match map. If the extension can't run (rare), the profile name is shown. No contact names ever leave the device. |
| G2 | A **pending follow-back request** when the original follow ends (Ana unfollows Ben while Ben's follow-back request to Ana is pending). | The pending request stays pending, consistent with 3.5 ("any pending request you sent them stays pending"). Ana can still approve or decline it. No new follow-back request can be sent once eligibility ends. |
| G3 | **Crossing requests** (both people request each other at the same time). | Two independent pending requests. Approving one does not auto-approve the other, because every follow needs approval. |
| G4 | **Location tag picker.** | Free-text place search using Apple MapKit's local search. The app requests no location permission in this version. The post stores the place name and coordinates chosen by the user. |
| G5 | **Story text overlays.** | Burned into the media on the device (image compositing for photos, a video composition layer for videos, during the same export pass that transcodes the video). Simplest to render consistently and "save to phone" includes the text. |
| G6 | **Video limits.** | 60 seconds maximum, enforced in the picker and the export step. Export to 1080p H.264 MP4 with the moov atom at the front so playback can start before download completes. The server records duration metadata supplied by the client and does not re-encode. |
| G7 | **"You're all caught up".** | The server stores, per user, the newest post timestamp they had seen when they last left the feed. The feed shows the marker at that boundary. |
| G8 | **Apple reviewer sign-in.** | A test phone number with a fixed code is configured in Supabase Auth (a built-in feature that skips SMS). It is given to Apple in the TestFlight review sign-in fields. It is a real account in the real database; the owner should keep its posts harmless. |
| G9 | **iOS minimum version.** | iOS 18. The limited-contacts APIs the spec relies on (4.1) exist only from iOS 18, and iOS 18 runs on the same iPhones as iOS 17 (iPhone XS, XR and later), so nothing is lost by choosing it. iPhone 8, X and older are not supported. |

---

## 2. Technical choices

Guiding constraints: one owner, 5 to 10 users at launch growing to hundreds, free tiers first with a smooth paid path, iOS is the priority, and the core rules must be enforced by the server and be testable automatically.

| Area | Choice | Why |
|---|---|---|
| **iOS app** | Native Swift (Swift 6, SwiftUI, Xcode 26), minimum iOS 18. | See 2.1 for the shared-codebase decision. Native gives first-class access to everything the spec leans on: iOS 18 limited contacts and `ContactAccessButton`, Notification Service Extension for on-device name display, AVFoundation video export with overlays, Dynamic Type for older users, text-code autofill, TestFlight. |
| **Backend** | **Supabase** (hosted Postgres with row-level security, Auth with phone OTP, Edge Functions, Realtime, Database Webhooks). Start on the **Free** plan. | Postgres with row-level security is the best fit for a follow graph with strict visibility rules, and the rules can be tested automatically with SQL tests. Free plan verified 2026-10-31: 500 MB database, 50,000 monthly active users, 500,000 function invocations, Realtime 200 concurrent connections, projects pause after one week of inactivity. Pro is 25 USD/month when needed and never pauses. |
| **Login and text codes** | Supabase Auth phone sign-in with **Twilio Verify** as the provider. Twilio **Verify Geo Permissions** set to allow the United States only. | Supabase supports Twilio Verify directly (Verify Service ID in the dashboard). Twilio's docs state Verify can be used for verification texts without A2P 10DLC registration, which otherwise takes a business registration and weeks. Price verified 2026-10-31: 0.05 USD per successful verification plus 0.0083 USD per US SMS. Geo Permissions block codes to non-US numbers at the provider, which enforces spec 2 and scenario 10 server-side and prevents SMS-pumping fraud costs. |
| **Media storage** | **Cloudflare R2** (S3-compatible object storage), private bucket, presigned URLs issued by an Edge Function. | Supabase Free includes only 1 GB of file storage, which about fifty 60-second videos would fill. R2's free tier (verified 2026-10-31) is 10 GB-month storage, 1 million writes and 10 million reads per month, and **egress is free**, so video viewing never produces a bandwidth bill. Beyond free: 0.015 USD per GB-month. Using R2 from day one avoids a storage migration later. |
| **Invite web page** | Static HTML on **Cloudflare Pages**, on the free `*.pages.dev` subdomain. A custom domain is optional. | Free, no server. One Cloudflare account covers R2, Pages and the keep-alive job. |
| **Push notifications** | Apple Push Notification service (APNs) called directly from a Supabase Edge Function using a token-signing key (.p8). Triggered by a Database Webhook on a `push_outbox` table. | Free, no third-party push SDK, no extra data processor to list in the privacy policy. Android later would add Firebase Cloud Messaging in the same function. |
| **Keep-alive** | A Cloudflare Worker cron trigger (free tier) that calls one cheap read endpoint on the Supabase project once a day. | Prevents the Free plan's one-week inactivity pause during quiet weeks. Remove it when the project moves to Pro. |
| **Crash and error logs** | Apple's built-in crash reporting (TestFlight and Xcode Organizer) for the app. Supabase's built-in logs for the server. No third-party logging SDK. | Satisfies spec 11 and A7 with no extra tracker, no extra cost and nothing new to disclose. Server logs must never include post content, messages, or contact data (see 4.6). |
| **Source control and CI** | Private GitHub repository. GitHub Actions (free minutes) runs the database tests on Linux. **Xcode Cloud** (Apple's hosted CI, 25 compute hours per month included with the developer membership; verify the current allowance in App Store Connect) builds, tests and uploads to TestFlight. | Keeps iOS builds off paid macOS runners. |
| **Local development** | Supabase CLI running the full stack in Docker on the owner's Mac; Xcode simulator; a seeded test database. | Everything can be run and tested without touching production. |
| **Key libraries** | `supabase-swift` (official client), `PhoneNumberKit` (number parsing and E.164 formatting), Apple frameworks only otherwise (Contacts, ContactsUI, AVFoundation, PhotosUI, MapKit, CryptoKit, UserNotifications, MessageUI). | Few dependencies, all actively maintained. |

### 2.1 Shared iOS and Android codebase: decision

**Decision: do not share a client codebase. Build the iOS app natively. Android follows later as a second native client against the same backend.**

The spec allows a shared codebase only if it "doesn't delay or compromise iOS". A cross-platform framework (React Native or Flutter) would compromise iOS in the places this product depends on most:

- iOS 18 limited contacts access and the system `ContactAccessButton` (spec 4.1) need the latest Contacts APIs; cross-platform plugins lag these by months and often expose only full-or-nothing access.
- On-device name display in notifications (spec 3.2, G1) needs a Notification Service Extension, which is native code either way.
- Story creation (camera, 60-second video export with burned-in text) and fast media playback are weakest through a bridging layer.
- Readability for older relatives relies on Dynamic Type and native accessibility behaviour, which work automatically in SwiftUI.

What is shared is the part that holds every rule: the database schema, access policies, server functions and the invite site. An Android client later is a thin UI over the same API, roughly the size of the iOS UI layer. This is the cost of the decision and the owner has accepted it implicitly by making iOS the priority.

### 2.2 Cost at the expected scale

| Item | 5 to 10 users (launch) | A few hundred users | Verified? |
|---|---|---|---|
| Apple Developer Program | 99 USD/year | 99 USD/year | Yes (Apple enrollment page, 2026-10-31) |
| Supabase | 0 (Free) | Likely 25 USD/month (Pro) once the database nears 500 MB, or sooner for daily backups and no pausing | Prices yes; the point at which Pro is needed is an estimate |
| Cloudflare R2 | 0 (under 10 GB) | Estimate 2 to 6 USD/month at 150 to 400 GB of media | Prices yes; volume is an estimate |
| Cloudflare Pages and Worker | 0 | 0 | Yes |
| Twilio Verify | Estimate under 2 USD/month (a few sign-ins) | Estimate 3 to 10 USD/month | Unit prices yes; volume is an estimate |
| APNs, Xcode Cloud, crash reports | 0 | 0 | Xcode Cloud allowance: verify in App Store Connect |
| Domain (optional) | 0 using `pages.dev`; about 10 to 15 USD/year if bought | same | Estimate |
| **Total** | **About 99 USD/year plus a few dollars of texts** | **Estimate 30 to 45 USD/month plus 99 USD/year** | |

Cloudflare may require a payment card on file to enable R2 even while usage stays within the free tier. Twilio requires upgrading from the trial account (a small prepaid balance, around 20 USD) before it will text numbers you haven't pre-verified. Both are marked as estimates.

---

## 3. Architecture

### 3.1 Components

```
┌───────────────────────────── iPhone ─────────────────────────────┐
│  Connectcha app (SwiftUI)                                         │
│   ├─ Onboarding / Auth        ├─ Feed, Posts, Likes               │
│   ├─ Contacts & Matching      ├─ Stories (create, tray, viewer)   │
│   ├─ People / Requests        ├─ Inbox & Conversations            │
│   ├─ DisplayNames (local)     ├─ Activity & Settings              │
│   └─ Media pipeline (resize, transcode, upload)                    │
│  Notification Service Extension (rewrites names from local map)   │
│  App Group container: match map {userId → contact id, name}       │
└──────────────┬─────────────────────────────┬──────────────────────┘
               │ HTTPS (Supabase client, JWT) │ HTTPS (presigned PUT/GET)
┌──────────────▼──────────────┐   ┌───────────▼──────────────────┐
│ Supabase project            │   │ Cloudflare                   │
│  Auth (phone OTP → Twilio   │   │  R2 bucket "media" (private) │
│       Verify, US only)      │   │  Pages: invite site          │
│  Postgres + RLS + RPCs      │   │  Worker cron: keep-alive     │
│  Realtime (messages)        │   └──────────────────────────────┘
│  Edge Functions:            │
│   create-upload-urls        │──► R2 (sign PUT)
│   get-media-urls            │──► R2 (sign GET)
│   send-push  ◄── DB webhook │──► APNs
└─────────────────────────────┘
```

Design rules that apply everywhere:

1. **All writes that carry a business rule go through Postgres functions (RPCs)** marked `SECURITY DEFINER`, which check `auth.uid()` themselves. Clients never insert directly into tables that encode the follow graph, posts, stories or messages.
2. **All reads go through row-level security (RLS).** Every table has RLS enabled with `SELECT` policies; a client can only ever see rows the policies allow, regardless of the query it writes.
3. **One visibility helper, `can_view_content(viewer, author)`**, is used by every policy and function that decides whether someone may see posts, stories or profile content. It returns true only when `viewer = author` or an approved follow exists from viewer to author. Blocking (section 13) will later be added inside this one function.
4. **The server never learns a contact name, never stores a non-user's number, and never returns a phone number or phone hash of anyone to anyone.**

### 3.2 Data model

All tables live in schema `public` unless noted. `auth.users` is managed by Supabase Auth and holds the phone number used to sign in. Timestamps are `timestamptz`.

| Table | Columns (key ones) | Notes |
|---|---|---|
| `profiles` | `id uuid PK = auth.users.id`, `first_name`, `last_name`, `bio`, `avatar_key`, `phone_hash text UNIQUE`, `created_at` | `phone_hash` = SHA-256 of the E.164 number (with leading `+`), maintained by a trigger on `auth.users` so it follows number changes. Phone numbers themselves stay only in `auth.users`, which clients cannot read. |
| `follows` | `follower_id`, `followee_id`, `created_at`; PK (follower, followee) | An approved, active follow. |
| `follow_requests` | `id`, `requester_id`, `target_id`, `source` (`contact` or `follow_back`), `status` (`pending`, `approved`, `declined`, `cancelled`), `created_at`, `resolved_at` | Partial unique index on (requester, target) where status = pending. Declines are invisible to the requester (A1). |
| `posts` | `id`, `author_id`, `caption`, `location_name`, `location_lat`, `location_lng`, `responses_enabled bool`, `published_at` (null until all media ready), `created_at` | Hard-deleted; messages that referenced it keep `kind = post_response` with `post_id` set null and display "Post no longer available". |
| `media` | `id`, `owner_id`, `post_id` (nullable), `story_id` (nullable), `kind` (`photo`/`video`), `object_key`, `thumb_key`, `width`, `height`, `duration_s`, `bytes`, `position`, `status` (`pending`/`ready`), `created_at` | Object keys are random UUIDs under `media/{owner_id}/`. Deleting a post or story deletes rows; a nightly Edge Function job removes orphaned R2 objects (M5). |
| `likes` | `post_id`, `user_id`, `created_at`; PK (post, user) | |
| `stories` | `id`, `author_id`, `media_id`, `location_name`, `replies_enabled`, `created_at`, `expires_at = created_at + 24h` | No job needed to expire: visibility policies compare `expires_at` to `now()`. Archive = author's own rows past expiry. |
| `story_views` | `story_id`, `viewer_id`, `viewed_at`; PK (story, viewer) | |
| `conversations` | `id`, `user_a`, `user_b` (`user_a < user_b`), `created_at`, `last_message_at`; UNIQUE (user_a, user_b) | One per pair (spec 7). |
| `messages` | `id`, `conversation_id`, `sender_id`, `kind` (`text`, `post_response`, `story_response`, `story_reaction`), `body`, `post_id` (nullable FK, on delete set null), `story_id` (nullable FK, on delete set null), `created_at` | Story previews check `stories.expires_at` at render time to show "Story no longer available" (A2). |
| `conversation_reads` | `conversation_id`, `user_id`, `last_read_at` | Drives the Inbox badge. |
| `feed_seen` | `user_id PK`, `seen_through` | "You're all caught up" marker (G7). |
| `activity` | `id`, `recipient_id`, `actor_id`, `type` (`follow_request`, `request_approved`, `like`), `post_id`, `created_at` | Likes are grouped by post in the client ("Mom and 3 others"). |
| `bells` | `user_id`, `target_id`; PK | "Notify me" on target's posts and stories. |
| `notification_settings` | `user_id PK`, `requests`, `messages`, `likes`, `bells` (all bool, default true) | |
| `device_tokens` | `token PK`, `user_id`, `platform`, `updated_at` | |
| `push_outbox` | `id`, `recipient_id`, `type`, `payload jsonb`, `created_at`, `sent_at` | Written by triggers; a Database Webhook on insert calls `send-push`. |

**What is deliberately absent:** any table of contacts, contact names, non-user phone numbers, matched-contact sets, follower counts, or analytics events.

### 3.3 Access rules (row-level security)

| Table | SELECT allowed when | Writes |
|---|---|---|
| `profiles` | Always for any signed-in user, but **only** columns `id, first_name, last_name, avatar_key`; `bio` only when `can_view_content(auth.uid(), id)`. Implemented as two views (`profiles_minimal`, `profiles_full`) over a table with no direct client access. `phone_hash` is never exposed. | Own row only, via `update_profile`. |
| `follows` | `follower_id = auth.uid() OR followee_id = auth.uid()` (you see only your own edges, so nobody can read another person's lists or counts, spec 8.4) | RPCs only. |
| `follow_requests` | `requester_id = auth.uid()` (own outgoing, shown as "Requested" regardless of declined, A1) `OR (target_id = auth.uid() AND status = 'pending')` | RPCs only. |
| `posts` | `published_at IS NOT NULL AND can_view_content(auth.uid(), author_id)` | RPCs only. |
| `media` | Same rule as the parent post or story; own rows always. | RPCs plus Edge Functions. |
| `likes` | `user_id = auth.uid()` OR the post's author is `auth.uid()` (only the poster sees who liked). The **count** is exposed through a view `post_like_counts` readable when the post is visible. | RPCs only. |
| `stories` | `author_id = auth.uid()` (including expired, for the archive) OR (`expires_at > now()` AND `can_view_content(auth.uid(), author_id)`) | RPCs only. |
| `story_views` | Story's author is `auth.uid()` | RPC `mark_story_viewed`. |
| `conversations`, `messages`, `conversation_reads` | Participant only. | RPCs only. |
| `feed_seen`, `activity`, `bells`, `notification_settings`, `device_tokens` | Own rows only. | Own rows (direct upsert allowed for settings and tokens; RPCs otherwise). |
| `push_outbox` | No client access. | Triggers only. |

### 3.4 Server functions (RPCs)

All run as `SECURITY DEFINER`, derive the caller from `auth.uid()`, raise an error on any rule violation, and are the only write path for the tables above.

| Function | Rule enforced |
|---|---|
| `match_contacts(hashes text[])` → rows of (`hash`, `user_id`, `first_name`, `last_name`, `avatar_key`) | Pure read: joins the hashes to `profiles.phone_hash`. Writes nothing, logs nothing. Accepts at most 500 hashes per call. |
| `send_follow_request(target_id, target_phone_hash text)` | Allowed only if (a) `target_phone_hash` equals the target's stored `phone_hash` (proof the caller has the number), or (b) the target currently follows the caller (follow-back, spec 3.3). Rejects if a follow or a pending request already exists. Records `source`. Writes `activity` and `push_outbox` for the target. |
| `cancel_follow_request(id)` | Requester only. |
| `approve_follow_request(id)` → `{follow_back_available: bool}` | Target only, pending only. Creates the follow, writes `activity` and `push_outbox` for the requester. Returns whether the approver may now follow back (no existing follow or pending request in that direction). |
| `decline_follow_request(id)` | Target only. Sets `declined`; the requester sees no change (A1). |
| `unfollow(user_id)` / `remove_follower(user_id)` | Deletes the edge. Neither writes activity or push (spec 3.5). |
| `create_post(caption, location, responses_enabled, media_descriptors[])` → `post_id`, `media_ids` | Validates 1 to 10 items, caption ≤ 1,000 chars, video ≤ 60 s. Creates post with `published_at` null and media rows with `status = pending`. |
| `publish_post(post_id)` | Author only; requires every media row to be `ready`; sets `published_at`. Writes `push_outbox` for followers who have a bell on the author. |
| `update_post(post_id, caption, location, responses_enabled)` / `delete_post(post_id)` | Author only. Media can't be changed (spec 5.2). |
| `like_post(post_id)` / `unlike_post(post_id)` | Requires `can_view_content`. Writes `activity` (no push, spec 10). |
| `create_story(media_id, location, replies_enabled)` / `delete_story(id)` | Author only; media must be `ready`. Bell pushes as for posts. |
| `mark_story_viewed(story_id)` | Requires the story to be visible to the caller. |
| `respond_to_post(post_id, body)` / `respond_to_story(story_id, body, is_reaction)` | Requires the post or story to be visible to the caller, `responses_enabled` / `replies_enabled` true, and body ≤ 2,000 chars. Finds or creates the pair's conversation. Writes the message and `push_outbox`. This is the **only** way a conversation is created (spec 7). |
| `send_message(conversation_id, body)` | Participant only; requires an existing follow in **either** direction between the two (spec 7); otherwise raises `conversation_read_only`. |
| `mark_conversation_read(id)`, `mark_feed_seen(through)`, `set_bell(target_id, on)`, `update_profile(...)`, `register_device_token(...)` | Own data only. |

### 3.5 Edge Functions

| Function | Purpose |
|---|---|
| `create-upload-urls` | Caller passes media IDs it owns with `status = pending`; returns presigned R2 PUT URLs (15-minute expiry) for the object and thumbnail. After uploading, the client calls RPC `mark_media_ready(media_id, width, height, duration_s, bytes)`. |
| `get-media-urls` | Caller passes up to 100 media IDs; the function runs a query **as the caller** (forwarding their JWT so RLS applies) to filter to visible rows, then returns presigned GET URLs valid for 1 hour. The client caches URLs and media. |
| `send-push` | Receives a Database Webhook for each `push_outbox` insert; loads the recipient's `notification_settings` and `device_tokens`; sends to APNs with `mutable-content: 1` and a payload containing `type`, `actor_id`, `actor_profile_name`, and IDs needed for deep links. Marks `sent_at`. Removes tokens APNs reports as invalid. |
| `cleanup-orphans` (scheduled, daily) | Deletes R2 objects whose media rows are gone. |

### 3.6 How the design enforces the core rules

| Rule (spec) | Enforcement | Automated test |
|---|---|---|
| **Nobody sees posts or stories without approval** (principle 2, scenarios 2, 5, 14) | RLS on `posts`, `stories`, `media`, `likes` all route through `can_view_content`. Media bytes are reachable only via presigned URLs, which `get-media-urls` issues only for rows RLS lets the caller see. `remove_follower` and `unfollow` delete the edge, so the next query, URL request and realtime event are denied immediately. | SQL tests: pending requester, declined requester, removed follower and stranger each select zero rows and `get-media-urls` returns none; approved follower sees rows; story invisible to follower after `expires_at`, visible to author. |
| **Contacts are the only way to discover people** (principle 3, scenarios 1, 3, 4) | There is no endpoint that lists or searches users. `profiles_minimal` is readable but there is no way to enumerate it except by IDs you already hold, and IDs are obtained only from `match_contacts` results, your own follow edges, your requests, or your conversations. `send_follow_request` requires proof of the target's number (hash match) or an active follow from the target. | SQL tests: request with wrong hash fails; with correct hash succeeds; follow-back succeeds only while target follows caller; after target unfollows, follow-back request fails and hash request still works. |
| **Phone numbers are never shown** (principle 4, scenario 3) | `auth.users` is unreadable by clients; `phone_hash` exists only on the base `profiles` table, which has no client grants; views omit it; `match_contacts` echoes back only hashes the caller sent. No API returns a number. | SQL test: `SELECT phone_hash FROM profiles` as a client role is denied; views lack the column; `match_contacts` output contains only input hashes. |
| **Saved contact names stay on the device** (3.2, scenario 7) | The Contacts module exposes a type `ContactMatchRequest` that holds only hashes and local contact identifiers; nothing else can reach the networking layer. Display-name resolution is a client function over the App Group match map. Push rewriting happens in the on-device extension. | Swift unit test: a URLProtocol stub records every request body during a full matching run against a fixture address book and asserts none contains any fixture name. Type check: the networking layer has no API that accepts a `CNContact`. |
| **Non-users' numbers aren't kept** (4.2, scenario 8) | `match_contacts` is a read-only function; no table can hold a hash other than a user's own; Postgres statement logging stays off; the API gateway does not log bodies. The client stores the matched set (user IDs and contact identifiers) locally for the "newly on here" diff. | SQL test: after calling `match_contacts` with unknown hashes, no table row contains them (checked by scanning every public table for the hash text). Manual check in M3: run a match and search the Supabase Logs Explorer for a submitted hash; expect no hit. |
| **No follower lists or counts for others** (8.4, scenario 16) | RLS on `follows` restricts to your own edges; no count view exists for others; the request hint was removed (C2). | SQL test: user C selects `follows` and sees only rows involving C. |
| **Only the poster sees who liked** (5.3, scenario 11) | RLS on `likes` plus a count-only view. | SQL test. |
| **Responses are private** (5.4, scenario 12) and **messaging stops when no follow remains** (7, scenario 13) | Conversations are participant-only; `send_message` checks the follow in either direction; `respond_to_*` requires visibility and the poster's setting. | SQL tests for each. |
| **Non-US numbers can't sign up** (2, scenario 10) | Twilio Verify Geo Permissions allow US only; client validates `+1` before sending. | Manual: attempt with a non-US number; expect failure before any code is sent. Unit test for client validation. |

### 3.7 Client architecture notes

- **Modules:** `Auth`, `Contacts` (permission including `.limited`, `ContactAccessButton` for adding more, E.164 normalisation treating numbers without a country code as US, SHA-256 hashing, batching), `DisplayNames` (match map in the App Group container; resolves names everywhere, with profile-name fallback), `People` (People you know, requests, invites), `Feed`, `Posts`, `Stories`, `Messaging`, `Activity`, `Notifications` (registration, settings, deep links), `Media` (resize photos to 2048 px JPEG plus 400 px thumbnail; export video to 1080p H.264 with optional overlay; upload with retry), `Settings`.
- **Matching run:** on every foreground, read contacts, normalise, hash, call `match_contacts` in batches of 500, replace the local match map, diff against the previous set to show "X is now on here", and refresh the People tab.
- **Invites:** contacts with no match; "Invite" opens Messages with the prefilled text and the invite link via `MFMessageComposeViewController`. Non-US contacts show the country-code message instead.
- **State and caching:** in-memory models with a small on-disk cache for the feed, inbox and media URLs; media files cached through `URLCache`. No local database is needed at this scale.
- **Realtime:** subscribe to `messages` changes for the open conversation and to the inbox summary. Everything else refreshes on foreground and pull.
- **Accessibility and look:** SwiftUI with Dynamic Type throughout, minimum 44-pt tap targets, system light and dark appearance, a warm accent palette. Detailed visual design happens during M9.

---

## 4. Build milestones

Each milestone ends in something that runs and can be checked. Dependencies are listed; milestones with no shared dependency may be built in parallel. Acceptance criteria reference spec sections and section 15 scenarios (written as S1 to S17).

### M0: Foundations

**Scope:** Git repository with `ios/`, `supabase/`, `web/` folders. Supabase project created locally with the CLI; initial migration with the schema in 3.2, RLS enabled on every table, and the `can_view_content` helper. Xcode project with app target, Notification Service Extension target and App Group; SwiftUI shell with the five tabs from spec 8.5 as placeholders. GitHub Actions workflow running database tests on Linux. Xcode Cloud workflow building and testing on push.
**Dependencies:** none (owner setup items O1 to O4 in section 6 for the hosted project; local work can start immediately).
**Acceptance:** `supabase start` and `supabase db reset` succeed; the SQL test suite runs (even if empty) in CI; the app builds and launches to the tab shell on a simulator.

### M1: Sign-up and sign-in (spec 9.1 steps 1 to 3, 9.4)

**Scope:** Phone entry limited to US numbers with formatting and text-code autofill; code entry; name step (first and last required); optional profile photo (uploaded through the media pipeline's photo path to R2); session stored securely so users stay signed in; new device requires a new code. Twilio Verify wired up with Geo Permissions US only; a test phone number with fixed code configured in Supabase for Apple's reviewers and automated UI tests. Terms and privacy links on the first screen (URLs come from the owner; placeholder pages until then).
**Dependencies:** M0; owner items O2, O3.
**Acceptance:** A US number receives a code and lands in the name step; a non-US number is refused before any code is sent (S10); relaunching the app skips sign-in; signing in on a second simulator with the same number requires a new code; `profiles` row exists with a `phone_hash` and the client cannot read `phone_hash` (3.6).

### M2: Access rules and server functions, with tests

**Scope:** All RPCs in 3.4, all RLS policies in 3.3, views `profiles_minimal`, `profiles_full`, `post_like_counts`, triggers that write `activity` and `push_outbox`. A pgTAP test suite that seeds users with known phone hashes and follow states and exercises every row in 3.6. No UI.
**Dependencies:** M0.
**Acceptance:** The SQL suite passes in CI and covers S1, S2, S4, S5, S11, S12, S13, S14, S16 plus the phone-hash non-exposure and non-user discard checks. Reviewing the test file against 3.6 shows one or more named tests per row.

### M3: Contacts, People you know, invites, invite page (spec 4, 8.5, 9.1 steps 4 to 6, 9.3)

**Scope:** Contacts permission screen with the spec's explanation; full and limited access; `ContactAccessButton` to add people under limited access; matching run on foreground; People tab with "People you know" (per-person Request button, states: Request, Requested); the onboarding "People you know" step as a checklist with nothing preselected and one "Send requests (N)" button (C1); "X is now on here" prompt; invite list with Messages compose and the non-US message; the static invite page on Cloudflare Pages with iPhone instructions (TestFlight link placeholder until M10) and Android "Coming soon". Denied-permission state that still allows everything else.
**Dependencies:** M1, M2.
**Acceptance:** With a seeded user whose number is in the simulator's contacts, they appear under their saved name (S7); a non-user contact appears in Invites and "Invite" opens Messages with the prefilled text (S8); a non-US contact shows the country-code message and no compose sheet (S9); the Swift payload test proves no contact names were sent (S7); the Supabase Logs Explorer shows no submitted hash after a matching run (S8); denying contacts leaves posting and approving available (S17); limited access matches only the chosen contacts (4.1); the invite page shows the right branch on an iPhone and an Android user agent.

### M4: Following (spec 3.3 to 3.5, 8.1 to 8.4)

**Scope:** Follow requests screen (name per 3.2, "In your contacts" / "Not in contacts" label, photo; no mutuals hint per C2); approve and decline; follow-back prompt after approval with the "approved you and wants to follow you back" request on the other side; cancel request; unfollow; remove follower; own follower and following lists and counts; minimal profile with "Request to follow" only when eligible; profile as seen by a follower (bell and Unfollow present; posts grid empty until M5); People tab badge.
**Dependencies:** M3.
**Acceptance:** S1 (no way to reach or request a stranger), S2 (pending or declined requester sees only the minimal profile), S3 (follow-back flow; neither screen ever shows a number), S4 (after unfollow, follow-back is unavailable unless the number is in contacts), S5 (removed follower loses access with no notification), S6 (deleting the contact changes the displayed name to the profile name and keeps the follow), S16 (no other person's lists or counts anywhere in the UI).

### M5: Posts and feed (spec 5)

**Scope:** Create flow: pick 1 to 10 photos or videos, 60-second check, caption (1,000 chars), location via MapKit search, responses toggle; media pipeline (resize, transcode, presigned upload, `mark_media_ready`, `publish_post`) with progress and retry; feed newest-first with paging and "You're all caught up"; post view with heart and double-tap like, like count, poster-only likers list; edit caption and location; delete post; profile grid; empty-feed state per 9.2; `cleanup-orphans` function.
**Dependencies:** M4.
**Acceptance:** Media loads promptly on a throttled connection (Network Link Conditioner "3G" profile: first image within 2 seconds, video starts within 3 seconds); a 61-second video is refused; S11 (count for viewers, names for the poster); S15 (empty state shows requests and prompts, never filler); deleting a post removes it from followers' feeds on next refresh; a non-follower's `get-media-urls` call for the post's media returns nothing (manual check with a second account).

### M6: Stories (spec 6)

**Scope:** Create from camera or camera roll; text overlay burned in; location tag; replies toggle; story tray ordering (own story first per A3, then unseen, most recent first); viewer with sequential playback; seen list for the author; 24-hour visibility via policies; private archive; save to phone.
**Dependencies:** M5.
**Acceptance:** S14 (story disappears for followers after 24 hours, remains in the author's archive; tested by adjusting `expires_at` on a test row); a pending requester cannot see the story (S2); viewer list visible only to the author; saved story appears in Photos.

### M7: Messaging (spec 5.4, 6 interactions, 7)

**Scope:** "Message [name]" input under posts; story reply and emoji reaction; conversation screen with post and story previews ("Post no longer available", "Story no longer available"); Inbox list with unread badge; realtime updates; read-only state when neither follows the other.
**Dependencies:** M5, M6.
**Acceptance:** S12 (a response is visible only in the pair's conversation, never to other followers; verified with three accounts); S13 (after both follows end, the conversation is readable and sending fails with a clear message); a poster who doesn't follow the responder can reply; responses are blocked when the poster turned them off.

### M8: Activity and notifications (spec 10)

**Scope:** Activity list (requests, approvals, grouped likes); APNs registration asked last in onboarding (9.1 step 7); `send-push` Edge Function with the Database Webhook; Notification Service Extension that rewrites the sender's name from the App Group match map (G1); per-category settings; per-person bells with pushes on new posts and stories; badges on People and Inbox; deep links from notifications.
**Dependencies:** M4, M7.
**Acceptance:** Each row of the spec 10 table behaves as stated on a physical iPhone; a request from a contact arrives as "Mom requested to follow you" while the server payload contained only the profile name (inspect the payload in the Edge Function logs); turning off a category stops its pushes; bell off by default; likes and story views never push.

### M9: Polish, onboarding end-to-end, settings and legal (spec 8.6, 9, 11)

**Scope:** Visual design pass (warm palette, large text, Dynamic Type at the largest accessibility sizes, light and dark mode); full onboarding sequence in the spec's order; Edit profile (bio 150 chars); Settings with notification categories, support email, privacy policy and terms links, sign out; copy review for non-technical users; VoiceOver labels on all controls.
**Dependencies:** M1 to M8.
**Acceptance:** Onboarding runs start to finish on a fresh device in the spec's order with the notifications prompt last; every screen remains usable at the largest Dynamic Type setting; both appearances pass a visual check; the support email opens Mail.

### M10: TestFlight release and operations

**Scope:** `ITSAppUsesNonExemptEncryption = NO` in Info.plist; App Store Connect record, Test Information (beta description, feedback email, privacy policy URL), Beta App Review information (contact, sign-in with the test number and fixed code, notes explaining the contacts-only model); internal test group; first external build submitted for review; public link enabled and placed on the invite page; Cloudflare Worker keep-alive; weekly database backup job (`pg_dump` from GitHub Actions to a private location, since the Free plan has no automatic backups; verify current plan features); an `OPERATIONS.md` runbook covering the 90-day rebuild cadence, how to answer account-deletion emails, how to rotate the test account, and the Pro-upgrade trigger points.
**Dependencies:** M9; owner items O5 to O8.
**Acceptance:** A relative with no developer tools installs the app from the public link following only the invite page; the build is approved by Beta App Review; the runbook is complete.

---

## 5. Testing

| Layer | Tooling | Runs | What it covers |
|---|---|---|---|
| **Database access rules** | pgTAP against the local Supabase stack, seeded with fixture users (`ana`, `ben`, `dave`, `stranger`, `pending`, `declined`, `removed`) and fixture phone hashes. Each test sets `request.jwt.claims` to impersonate a user and asserts row counts and function outcomes. | Every push, in GitHub Actions (Linux). | Every row of table 3.6; scenarios S1, S2, S4, S5, S11, S12, S13, S14, S16; non-exposure of `phone_hash`; non-persistence of unknown hashes; message read-only state; story expiry; like visibility. |
| **Server functions** | Deno tests for the three Edge Functions with R2 and APNs calls stubbed; one integration test that signs a GET URL for visible and invisible media. | Every push. | `get-media-urls` returns URLs only for RLS-visible rows; `send-push` honours settings and strips nothing it shouldn't; payload contains no phone data. |
| **iOS unit tests** | XCTest. | Every push, in Xcode Cloud; locally on demand. | Phone normalisation (no country code → US, non-US detection), hashing, batching, match-map diffing ("now on here"), display-name resolution with fallback, media export limits (60 s, sizes), the **no-contact-names-on-the-wire** payload test (S7), notification payload rewriting in the extension. |
| **iOS UI tests** | XCUITest against the local stack with the test phone number and fixed code. | Nightly and before each TestFlight build. | Onboarding end to end (S10 refusal, S15 empty state, S17 denied contacts), request → approve → follow-back (S3), create post and see it as a follower, response appears in Inbox (S12). |
| **Manual scenario pass** | A checklist file `TEST_SCENARIOS.md` with S1 to S17 and the spec 10 table, run on two physical iPhones plus one simulator. | Before every external TestFlight build. | Everything requiring real SMS, real push, real contacts and real camera: S8, S9, S10, notifications, media performance under Network Link Conditioner. |
| **Privacy log check** | Manual, documented in the runbook. | At M3 and before launch. | Supabase Logs Explorer contains no submitted hashes, no message bodies and no captions; Edge Function logs contain no contact data. |

Rule for the build agent: a milestone is not complete until its automated tests exist and pass and the relevant manual scenarios are ticked in `TEST_SCENARIOS.md`.

---

## 6. Setup the owner has to do

### 6.1 Bare minimum to start, and when each service becomes necessary

The repository is `https://github.com/jkern-dev/connectcha.git` (created 2026-10-31). Only two things are needed to begin, and the build agent must not block on anything else:

| Stage | Needs | Why that is enough |
|---|---|---|
| **M0 to M2, and most of M3 to M7 on the simulator** | GitHub repo; Docker Desktop and the Supabase CLI on the Mac; Xcode. **No hosted accounts.** | The Supabase CLI runs the whole backend locally (Postgres, Auth, Storage, Edge Functions). Sign-in uses Supabase's fixed-code test phone numbers, so no SMS provider is needed. Media code is written against the S3 protocol and pointed at the local Supabase Storage S3 endpoint; switching to R2 later is a configuration change, not a code change. |
| **First test with real phones and real users** (end of M5 or so) | Hosted Supabase project (Free); Twilio Verify (paid balance, estimate 20 USD); Cloudflare R2 (free tier). | Real devices need a reachable server, real sign-ups need real texts, and media must live somewhere with enough space. |
| **M8 push notifications** | Apple Developer Program (99 USD/year). | APNs keys and push entitlements require paid membership. Everything before M8 runs on the simulator or, for a single personal iPhone, with a free Apple ID in Xcode. |
| **M10 TestFlight** | Apple Developer Program; Cloudflare Pages (invite page); privacy policy and terms URLs; support email. | Required by Apple's TestFlight submission. |
| **Optional, any time** | Xcode Cloud, GitHub Actions, custom domain. | CI and a nicer address. Tests can be run locally until then. |

Items marked (blocking) below hold up the milestone shown. Everything else can be done any time before M10.

| # | Item | Cost | Needed by |
|---|---|---|---|
| O1 | **GitHub account** and a private repository `connectcha`; invite the build agent. | Free | M0 |
| O2 | **Supabase account** (sign in with GitHub) and one project, Free plan, region closest to your users (US). Share the project URL and keys with the build agent through a secrets channel, not chat. | Free | M1 (blocking) |
| O3 | **Twilio account**, upgraded from trial (prepaid balance, estimate 20 USD); create a **Verify Service** named Connectcha; set **Verify Geo Permissions** to allow only the United States and enable Fraud Guard; copy the Service SID into Supabase Auth phone provider settings (provider: Twilio Verify). | Pay as you go, about 0.06 USD per sign-in | M1 (blocking) |
| O4 | **Cloudflare account**; enable R2 (a card on file may be required, estimate) and create a private bucket `connectcha-media`; create an R2 API token for the Edge Functions; enable Pages. | Free at launch | M3 for Pages, M5 for R2 (blocking) |
| O5 | **Apple Developer Program**, Individual enrollment, using your legal name on your Apple Account. Then in App Store Connect: create the app record, bundle ID, an APNs authentication key (.p8), and enable Xcode Cloud. | 99 USD/year (verified) | M8 for push (blocking), M10 for TestFlight |
| O6 | **Legal documents:** a privacy policy and terms of service hosted at stable URLs (the invite site can host them). The privacy policy must state, in plain words: phone number is the account identity; contacts are hashed on the phone, matched, and non-users' numbers are discarded; saved names never leave the phone; messages are encrypted in transit and at rest but not end-to-end (spec 7); crash logs are collected via Apple; data retention and how to request deletion by email (spec 11). Use a lawyer or a reputable generator. | Estimate 0 to 300 USD | M1 for links (placeholders allowed), M10 (blocking: TestFlight test information asks for a privacy policy URL) |
| O7 | **Support email address** for the app and TestFlight feedback (a dedicated address is recommended). | Free | M9 |
| O8 | **TestFlight submission:** fill Test Information (beta description, feedback email, privacy URL) and Beta App Review information (your contact details; sign-in required with the test phone number and fixed code; notes explaining that discovery is contacts-only and how the reviewer can test with the second test account). Submit the first external build. Expect the first review to take a day or two; later builds of the same version may skip full review. After approval, enable the public link and set a tester limit (for example 500) so the link can't be overrun. | Included | M10 |
| O9 | **Optional domain** (for example `connectcha.app`) pointed at Cloudflare Pages. Without it the invite page lives on a `*.pages.dev` address, which works fine. | Estimate 10 to 15 USD/year | Any time |
| O10 | **Ongoing:** ship a new TestFlight build at least every 90 days (builds expire); keep the Twilio balance topped up; watch Supabase usage and upgrade to Pro (25 USD/month) when the database approaches 500 MB or you want automatic backups; review the weekly backup job runs. | See 2.2 | After M10 |

Supabase Free pauses after a week without API activity. M10 adds a daily keep-alive so this shouldn't happen, but if it ever does, unpausing is a button in the Supabase dashboard and takes a couple of minutes.

---

## 7. Risks and open items

| # | Risk or open item | Status and mitigation |
|---|---|---|
| R-A | **Beta App Review may require reporting, blocking or in-app account deletion before approving external testing** (spec R4, acknowledged). Guideline 1.2 lists these for apps with user-generated content and 5.1.1(v) requires in-app account deletion for any app with account creation. | Already accepted in the spec. The design keeps each a small addition (section 9). The owner should budget for one extra review cycle. The review notes should state that the app is a closed beta for family and friends with manual support by email. |
| R-B | **Free-tier operations:** Supabase Free has no automatic backups (verify) and pauses on inactivity. | Weekly `pg_dump` job and daily keep-alive in M10; move to Pro at the trigger points in O10. |
| R-C | **Media delivery through presigned R2 URLs isn't CDN-cached.** Fine for tens of users; with hundreds of users watching the same videos, first-byte times may grow. | Upgrade path without data migration: a Cloudflare Worker in front of the bucket that validates the Supabase token and serves through Cloudflare's cache. Not needed now. |
| R-D | **Video duration and size are enforced by the client only.** A modified client could upload longer or larger files. | Acceptable for a family beta. R2 bucket size alerts in the runbook; server-side checks can be added to `mark_media_ready` later. |
| R-E | **Phone hashes are not secret.** A SHA-256 of a phone number can be brute-forced, so hashing on the wire is hygiene, not protection. | The real controls are: the server never stores or logs submitted hashes, and no API returns a hash or number. Both are tested (3.6). The privacy policy should describe this honestly. |
| R-F | **iOS 18 minimum excludes iPhone 8, X and older.** | Accepted (G9). The invite page should say "iPhone XS or newer, running iOS 18 or later". |
| R-G | **Notification name rewriting depends on the Notification Service Extension running within its time budget.** | Fallback is the profile name. The extension reads a small local file, so timeouts should be rare. |
| R-H | **Xcode Cloud free allowance and Cloudflare's card requirement for R2 are unverified.** | Marked as estimates; neither changes the architecture. |
| R-I | **Working name "Connectcha" is unchecked for trademark and App Store conflicts** (spec 13.2). | The bundle ID and project names are easy to change before M10; the owner should decide the final name before the first external build to avoid a TestFlight name change. |
| R-J | **Reviewer test account** lives in production. | Keep its content harmless; rotate the fixed code after review; document in the runbook. |

### 7.1 Open items for the owner (not blocking the start of M0 to M2)

1. Privacy policy and terms URLs (O6).
2. Support email address (O7).
3. Final app name (R-I).
4. Whether to buy a domain (O9).

---

## 8. Suggested build order and parallelism

```
M0 ──► M1 ──► M3 ──► M4 ──► M5 ──► M6 ──► M7 ──► M8 ──► M9 ──► M10
  └──► M2 (parallel with M1; must finish before M3)
```

M2 is the heart of the plan. Build it early and keep its test suite green; every later milestone adds tests to it rather than working around it.

---

## 9. Room for the section 13 work (not built now)

| Section 13 item | Where it slots in later |
|---|---|
| Reporting | New `reports` table (reporter, target type and ID, reason) with an RPC; a "Report" entry in the post, story, message and profile menus. The owner reads reports in the Supabase dashboard at first. |
| Internal moderation tools | Initially the Supabase dashboard with SQL snippets in the runbook (remove content, suspend by setting a `suspended_at` column on `profiles` that `can_view_content` and the RPCs check). |
| Blocking | New `blocks` table; one added clause in `can_view_content`, `send_follow_request`, `match_contacts` output filtering, `respond_to_*` and `send_message`; a trigger that deletes follows between the pair. Because every visibility decision already passes through the helper, this is a small change. |
| In-app account deletion | RPC `delete_account` plus foreign keys already declared with `ON DELETE CASCADE` for the user's own rows; messages to others require the owner's decision (spec 13.2). A Settings button calls the RPC. |
| CSAM checks and reporting | Media already passes through two Edge Functions, which is where a scanning step would be inserted after legal review. |
| Minimum age and age check | A `birth_year` or attestation column on `profiles` and a step in onboarding. |
| Contact-matching rate limits and abuse detection | A `match_requests` counter table and a daily cap enforced inside `match_contacts`; a cap on `send_follow_request` per day. |
| Number changes and reassigned numbers | `phone_hash` already follows the auth phone through a trigger. A verified number-change flow is a Supabase Auth feature plus UI. Reassigned-number protection (for example re-verifying after long inactivity) is a policy decision. |
| Name check | Rename before M10 if possible (R-I). |

---

## Appendix A: Spec section to milestone map

| Spec section | Milestone(s) |
|---|---|
| 1 Principles | All; enforced in M2 |
| 2 Scope | M1 (US only), M10 (TestFlight) |
| 3 Accounts, identity, following | M1, M4 |
| 4 Contacts and invites | M3 |
| 5 Timeline and posts | M5, M7 (responses) |
| 6 Stories | M6, M7 (replies) |
| 7 Messaging | M7 |
| 8 Profiles and navigation | M0 (tabs), M4, M5, M9 |
| 9 Onboarding and invite page | M1, M3, M8 (notifications step), M9 |
| 10 Notifications | M8 |
| 11 Data and privacy | M2, M9 (support email, links), M10 (privacy log check) |
| 14 Confirmed defaults | A1 M4; A2 M7; A3 M6; A4 M5; A5 M3; A6 M5, M7, M9; A7 M10 |
| 15 Scenarios | See acceptance criteria per milestone and section 5 |
