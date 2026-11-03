# Design direction: the kitchen table

Status: chosen by the owner on 2026-11-03. Mock-ups only; no product code has changed yet.
Mock-ups: https://claude.ai/artifact/2rtbWKyXwATtjFiw4oXk7x (private canvas; eleven boards for this direction, plus the two directions that were explored and not chosen).

## Why

The first build copied Instagram's structure, not just its features: a row of ringed circles for stories, a square-card feed with a heart under each photo, a plus button in the middle of a five-tab bar, a three-column grid on every profile. Those four shapes are what make an app read as "a social network". The kitchen table replaces all four and keeps every feature and every privacy rule in `PRODUCT_SPEC.md`.

The idea: photos laid out on a table for the people you'd actually have round. Warm paper background, a serif for headings and captions, prints with a white border, and plain sentences instead of icons wherever a relative might hesitate.

## Vocabulary

The words change throughout the app. Accessibility identifiers can stay; visible labels and VoiceOver labels follow this table.

| Today (code and UI) | Kitchen table | Notes |
|---|---|---|
| Feed / Home | Home | Day headings: Today, Yesterday, then dates |
| Story / stories tray | Snapshot / Today's snapshots | Subheading "gone tomorrow"; viewer for your own says "Looked at by Ana, Ben and Mom" |
| Like | Lovely | Sun icon, button reads "Lovely · 1"; the count is visible only on your own posts, as today |
| Respond / reply to post | Write back to Ana | Plain link under the photo; opens the one-to-one conversation |
| Inbox / messages | Letters | "Between you and one other person. Nobody else can read them." |
| Conversation | A letter thread | A reply to a post carries the photo as "Written on the back of your photo" |
| Create / post | Share | Two kinds: "Photos for the table" and "Snapshot · gone tomorrow"; caption field is "On the back" |
| Caption | A line on the back | Italic serif |
| Follow request (incoming) | Waiting for your yes | Buttons "Yes, let Dad in" and "Not now", with a sentence saying what yes means |
| Follow request (outgoing) | Asked | Shown as a quiet word, not a button |
| Follow | Ask to follow / Following | Unchanged in meaning |
| People | Your circle | Sections: Waiting for your yes, People you know, Not here yet |
| Profile (other) | Someone's page | Filmstrip of their photos instead of a grid; a note that counts are never shown |
| Profile (own) | You | Also the way into Lately and Settings |
| Activity | Lately | "What people in your circle did with your photos" |
| Story archive | Past snapshots | "Only you can see the ones that have gone" |

## Tokens

Colours (light mode; dark mode is a later pass and should stay warm, not black):

| Role | Value |
|---|---|
| Paper (screen background) | `#F6F1E8` |
| Card | `#FFFFFF` |
| Soft fill (secondary buttons, fields) | `#FBF8F2` |
| Ink (primary text) | `#2B211A` |
| Body (captions, longer text) | `#3B2F27` |
| Muted (secondary text) | `#7A6A5E` on cards; use `#6B5B4F` for text under 15 pt on paper, where `#7A6A5E` is just under 4.5:1 |
| Walnut (accent, primary buttons, active tab) | `#8A5A3C`, pressed `#5E3A24` |
| Walnut tint (your own message bubbles, segmented background) | `#E9DCCB` |
| Hairline / divider | `#E2D7C8` on paper, `#F0E8DC` inside cards |
| Border (secondary buttons) | `#D9CBB9` |
| Inactive tab | `#5B4A3F` |

Type:

- Headings, day labels, captions and the wordmark: a serif. The mock-ups use Fraunces (SIL Open Font License, free to bundle). The fallback that costs nothing is the system serif, `Font.system(.title, design: .serif)`, which is New York on iOS and already scales with Dynamic Type. Decide once; both work.
- Everything else: the system sans (SF). Body 16 to 17 pt, secondary 13 to 14 pt, buttons 16 to 17 pt semibold.
- Captions are italic serif at 17 pt in the feed, 18 pt in a snapshot.

Shape:

- Cards: 18 pt radius, shadow `0 1 3 rgba(43,33,26,0.10)`, no border.
- Buttons and fields: full pills (half the height). Primary is walnut with white text; secondary is soft fill with a 1.5 pt border.
- Prints (snapshots, the Share tray, the sign-in decoration): white, 6 pt radius, 6 pt inner padding, a stronger shadow, rotated between -3° and +3°. The rotation is decorative; keep it off under Reduce Motion is not needed because nothing moves, but do keep it off for the large-text layout, where prints become plain rows.
- Spacing: 20 pt side gutters, 12 pt between stacked cards, 18 to 22 pt between sections.

## Navigation

- Three tabs: Home, People, You. No centre plus button. No Inbox tab.
- Home's top bar carries the date, the wordmark, the Letters button with an unread count, and the walnut Share button.
- You's top bar carries Lately (with a count) and Settings.
- Share is a sheet from anywhere Share appears. Looking at a snapshot is a full-screen cover.
- Letters, a conversation, Someone's page and Lately are pushed pages with a back link that names where you came from ("Home", "Letters", "You").

## Screen by screen

The right column names the SwiftUI file that changes. Nothing below the view layer changes; models and the API stay as they are.

| Board | What changes | Where |
|---|---|---|
| Home | Day-grouped list; first post of the day as a large card, later ones as a thumbnail row; snapshot pile at the top; "Lovely" and "Write back to X" under each card | `Feed/HomeTab.swift`, `Feed/PostCard.swift`, `Stories/StoryTray.swift` |
| Looking at a snapshot | One print on paper, caption underneath, thin progress bars, "Write back to Mom…" field and a Lovely button in a bottom bar; tap zones unchanged | `Stories/StoryViewerView.swift` |
| People | Title "Your circle" with the one-line rule; request card with the explaining sentence; "People you know" and "Not here yet" as grouped cards | `People/PeopleTab.swift` |
| Someone's page | Large name, status line, italic bio; "Your letters" (only when a thread exists, D-26) and "Following"; "Tell me when Ana shares something" row; horizontal filmstrip; privacy note | `Profile/ProfileView.swift` |
| You | Name and bio with "Change your photo or words"; today's snapshot card with who looked; "Your photos" filmstrip; rows for Past snapshots, Who can see your photos, Your number and privacy | `Profile/MyProfileTab.swift`, `Settings/SettingsView.swift` |
| Lately | Day-grouped cards; incoming requests answerable inline; unread rows have a walnut left edge | `Activity/ActivityView.swift` |
| Letters | One card per thread with name, time, "About your photo" line when the last message was a write-back, italic preview; "New letter" button | `Messaging/InboxTab.swift` |
| A conversation | Day dividers in serif; theirs white left, yours walnut tint right; a write-back shows the post as a small quoted card; composer "Write to Ana…" with a photo button | `Messaging/ConversationView.swift` |
| Share | Segmented choice Photos / Snapshot; chosen media as tilted prints with remove buttons and "Add more"; "On the back" caption card; Where row; "Let people write back" toggle; one sentence on who sees it; "Share with your circle" | `Posts/CreatePostView.swift`, `Stories/CreateStoryView.swift`, `Posts/CreateTab.swift` becomes a sheet |
| Sign in | Three prints as decoration, wordmark, the one-line promise, number field, "Text me the code", the rule about the number | `Auth/SignInFlow.swift`, then `Onboarding/*` in the same voice |
| Home at the largest text size | Snapshot pile becomes one row; Share and Letters become two full-width buttons; the two actions under a photo stack; nothing hidden, no text shrinks | `DesignSystem/Theme.swift` (`AdaptiveStack` already does the stacking) |

## Rules that must survive the restyle

- Names are always the saved contact name (`DisplayNames`); the mock-ups show "Mom" and "Dad" for that reason.
- Nobody sees another person's follower list or counts, including you on your own page. The only counts shown are your own Lovely counts and unread counts.
- A conversation can only start from a write-back (spec 7, D-26). "New letter" on the Letters page lists people you already have a thread with or who have written to you; it is not a way to message someone cold.
- No public comments anywhere; "Write back" always lands in a letter.
- Discovery is contacts only; "Your circle" has no search beyond your own contacts.
- Pushes keep their templates (D-29); only the words change ("Mom wrote back about your photo").

## Suggested order when implementation starts

1. Tokens and type in `Theme.swift`; the serif decision; button styles become pills.
2. Tab bar to three tabs; Home top bar with Share and Letters; Share as a sheet.
3. Home: day grouping, the snapshot pile, the new card.
4. People, Someone's page, You, Lately.
5. Letters and the conversation.
6. Share and the snapshot viewer.
7. Sign-in and onboarding copy.
8. Re-run the UI suite; the tests find controls by accessibility identifier, so most changes are label strings in the tests (`Like` becomes `Lovely`, `Inbox` becomes `Letters`, the Create tab disappears in favour of the Share button).

## Open for the owner

- Font: bundle Fraunces or use the system serif. Fraunces has more character; the system serif is free of any file to ship and renders identically in every text size.
- The word "Lovely". Alternatives that fit the voice: "Love it", "Warms my heart" (too long for a button), a plain heart icon with "Love". The mock-ups use "Lovely".
- Whether Lately should also be reachable from Home when there is something new. The mock-ups keep it under You to leave Home calm.
