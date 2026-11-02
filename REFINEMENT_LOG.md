# Refinement log

One entry per pass after M9. Each pass: use the app as a non-technical relative would on both simulators, note what is confusing, slow, ugly or fragile, fix it, re-run the tests and the scenario checklist, commit.

## Pass 0 (2026-11-02): state at the end of M8

Observed while building, fixed before refinement started:

- Light-mode text fields rendered black (asset colour components without a decimal point are read on a 0–255 scale). Fixed in M1.
- Contacts revoked after names were learned kept stale saved names. Now cleared (D-13).
- Media URL cache survived sign-out. Now cleared (D-19).
- Response RPCs return a receipt, not a message; the viewer showed "Something went wrong" after a reaction. Fixed (D-25).
- Reaction emoji render as a missing-glyph box in the iOS 26.3 simulator used here; bytes are correct (checked in the database) and real phones render them. Left as a known simulator quirk.

## Pass 1 (2026-11-02): largest text, first-run feel

Used both simulators at the default size and at the largest accessibility size (AX5), light and dark.

Changed:
- At AX5, Approve/Decline, Request/Invite, profile count tiles and action pills now stack vertically instead of hyphenating side by side (`AdaptiveStack`). Post headers put the time and place on their own line. Inbox rows put the time under the name. Story tray labels get two lines and a wider slot.
- Tapping "Requested" in People used to cancel the request immediately; it now asks first ("Cancel request" / "Keep waiting").
- Home showed a blank area while the first feed load ran; it now says "Loading your feed…".
- The app had no icon; a placeholder (terracotta with a white C, dark and tinted variants) replaces the blank tile. The owner should replace it with real artwork (OPEN_QUESTIONS Q1 covers the name).

Observed and left alone:
- Emoji render as a missing-glyph box in this simulator runtime (bytes are correct; phones render them).
- Test artifacts ("Pipeline Tester", "Sasha Spare") appear in the data after the test suites run; `make reset` clears them. The demo script always resets first.

## Pass 2 (2026-11-02): screen tour

Walked all sixteen main screens as Josh with the screenshot tour (`ScreenshotTourUITests`, `TEST_RUNNER_CONNECTCHA_TOUR=1`): Home, story viewer, likers, Activity, People, another person's profile, Create, New post, New story, Inbox, a conversation, Profile, Followers, Story archive, Edit profile, Settings.

Changed:
- Message previews said "Responding to Josh Kern's post" inside Josh's own conversation; they now say "your post" / "your story" when the post belongs to the reader.

Observed and left alone:
- Activity groups likes newest-liker-first ("Priya Nair and 3 others liked your post"); the spec's example order ("Mom and 3 others") is not a rule.
- Everything else read clearly at the default size; no truncated labels, no overlapping controls, consistent warm palette in light mode (dark mode checked in pass 1).

The pass produced one copy change and nothing structural, which is the stopping point the brief describes.
