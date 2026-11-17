# Next product features to explore

**Status:** Candidate list, not a commitment. Nothing here is specified, designed or built.
**Date:** 2026-11-16
**Written from:** the head-of-product view, as if Connectcha were already live in the App Store. It covers user-facing features only.

Companion files: `PRODUCT_SPEC.md` (what exists today and the principles), `DESIGN_DIRECTION.md` (the kitchen table look and the words the app uses, such as Snapshots and Letters).

## How to use this file

Pick a feature, then write its spec before any code: what the person sees, the rules, and which sections of `PRODUCT_SPEC.md` change. Several features below are listed as out of scope in spec section 12; choosing one means revising that section and logging the decision in `DECISIONS.md`.

Not covered here: the safety and compliance work in spec section 13.2 (reporting, blocking, moderation, age checks, number changes). That work is required before a public launch regardless of which features are chosen, and it is tracked in the spec.

## The test every feature must pass

A feature belongs here only if it makes Connectcha better at being the place a family stays close, without breaking the principles in spec section 1:

- Contacts are the only way to discover people.
- Nobody sees your posts unless you approved them.
- No algorithm and no ads.
- No popularity signals.
- Simple and readable, including for older relatives.

## Explore first

| # | Feature | What the person gets | Why it matters | Spec today |
|---|---|---|---|---|
| 1 | **Circles** (choosing who sees a post) | Send a post or Snapshot to a named group such as "Immediate family" or "College friends" instead of every follower. | People post more, and more honestly, when they control the audience. It is the biggest lever on how often people post. | Out of scope (12, "close friends lists or per-post audiences"); 5.2 says every post goes to all followers. |
| 2 | **Shared family albums** | An album several people add to, such as "Thanksgiving 2026" or "Nora's first year". It stays put instead of scrolling away. | Turns the app from a feed into a place the family keeps things, which is the strongest reason to stay. | New. |
| 3 | **Photos and voice notes in Letters** | Reply with a photo, or record a short voice note instead of typing. One-to-one only, no read receipts. | A grandparent who won't type will record 20 seconds of voice. Replying to a photo with a photo is the natural move. | Out of scope (12); 7 says text and emoji only. |
| 4 | **Group Letters for a family** | One conversation for a household or sibling group, limited to people who already follow each other. | The daily back-and-forth happens in groups. Without this it stays in iMessage. | Out of scope (12, "group chats"). |
| 5 | **"On this day" memories** | A private resurfacing of your own posts and archived Snapshots from past years, with one tap to share again. | A reason to open the app that is not a notification nag, and a reward for having posted. | New. It must not become a re-engagement push (12). |

## Explore next

| # | Feature | What the person gets | Why it matters | Spec today |
|---|---|---|---|---|
| 6 | **Print and keep** | Order a photo book or prints from an album or a year of posts, or send a card to a relative. | Fits the audience, and it is the natural paid feature for a product that will never carry ads. | Payments are out of scope (12), with paid extras "considered after the beta". |
| 7 | **Birthdays and occasions** | Opt in to share a birthday. Followers get a quiet reminder and a one-tap way to send a Letter or a photo. | A small feature that creates the family moments the product exists for. | New. |
| 8 | **Helper mode for less technical relatives** | A trusted family member sets up an account for a parent. A simplified "just show me the photos" home with larger controls. | Every older relative who gets stuck at sign-up takes a whole family branch with them. | New. Builds on principle 7. |
| 9 | **Snapshot keepsakes** | Pin favourite Snapshots to your profile as small collections ("The garden", "Road trip") instead of leaving them in the private archive. | Gives profiles some personality without any counts. | Out of scope (12, "Story Highlights"). |
| 10 | **Richer reactions without public comments** | A few warm quick replies on posts ("Love this", "Call me!") that arrive privately as a Letter. | Easier than typing, and it keeps the no-public-comments rule (5.4). | Extends 5.4 and the Snapshot emoji reaction in 6. |

## Explore later

| # | Feature | What the person gets | Why it matters | Spec today |
|---|---|---|---|---|
| 11 | **Home and lock screen widgets** | A widget showing the latest photo from family. | For people who would rather glance than open an app. | New. |
| 12 | **Android and numbers outside the US** | Relatives on Android or abroad can join. | Reach, not a feature, but one missing cousin weakens every circle and album above. | Out of scope (12). |
| 13 | **Tagging family in photos** | Tag people who can already see the post; the person tagged approves it. | Makes "photos of Dad" findable later and feeds memories and albums. | Out of scope (12, "tagging or mentioning people"). |

## Deliberately not explored

Reels, an Explore page, public comments, follower counts, streaks and "you haven't posted in a while" nudges. Each would grow usage in the short term and erode the reason people chose this app.

## Recommendation

If only one bet is made, make it Circles and shared albums together. Circles makes people comfortable posting; albums give the family something that accumulates.

## Open questions to settle when a feature is picked

- **Circles:** can a follower tell they were left out of a circle? (Recommendation: no, never.) Do circles apply to Snapshots as well as posts?
- **Shared albums:** who can add people to an album, and can someone see album photos from a contributor they do not follow?
- **Group Letters:** must every member follow every other member, or only the person who started the group?
- **Voice notes:** how long, and are they kept forever like other Letters?
- **Print and keep:** which print partner, and does taking payment change the App Store and privacy position?
