# Design direction: the kitchen table

Status: chosen by the owner on 2026-11-03 and implemented in the app the same day (D-32). The sections below describe the direction; "Where it differs from the mock-ups" at the end lists the small departures made while building.
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

## Choices made when building (D-32)

- Font: the system serif (New York) through `Font.serif(_:)` in `Theme.swift`. No font file to ship, identical rendering at every text size; Fraunces can be swapped in later by changing that one helper.
- The word "Lovely" stays. The count under a photo reads "4 found it lovely"; the list the poster can open is titled "Found it lovely".
- Lately stays under You (the clock in the top bar). Home carries no activity entry point, so it stays calm.

## Where it differs from the mock-ups

- Every photo on Home is a full card. The mock-ups showed later photos of a day as thumbnail rows; that would have taken "Lovely" and "Write back" off those photos, which are the two things a relative does most. The day headings carry the table feel on their own.
- Your own page keeps the counts spec 8.2 gives you ("People who follow you · 3 people", "People you follow · 3 people"). Other people's counts are never shown, as before.
- Letters has no "New letter" button. A letter can only start from a write-back (spec 7, D-26), so the button would have had nothing to offer.
- "Today's snapshots" shows "You" as the label on your own print rather than "Seen · You".
- The snapshot viewer sizes the print to the photo's shape (wide for landscape, tall for portrait) instead of a fixed tall print.
- Someone's page shows "Your letters" whenever a thread exists, even while your request is still pending, because the thread was started earlier under the rules (D-26).

## Wide windows: iPhone Duo unfolded

Mock-ups: https://claude.ai/artifact/JiBVhQoGXFJZQBBjPVwJUx (private canvas; three folded boards, four unfolded).

Built on 2026-11-12, driven by the horizontal size class only (`WideLayout` in `Theme.swift`), never by device or pose. At accessibility text sizes every screen stays single-column.

| Screen | Wide layout | Where |
|---|---|---|
| Home | Left page: header, snapshots in rows that wrap, the newest unread letter. Right page: the day's photos | `Feed/HomeTab.swift`, `Stories/StoryTray.swift` |
| Letters | Threads on the left, the open letter on the right; the newest thread opens by itself | `Messaging/InboxTab.swift`, `Messaging/ConversationView.swift` (`embedded`) |
| Looking at a snapshot | The print and its tap zones on the left; who it is from, "Next on the table" and the reply bar on the right | `Stories/StoryViewerView.swift` |
| Share | Covers the whole window instead of a sheet; prints on the left, the words and the Share button on the right | `Posts/CreateTab.swift`, `Posts/CreatePostView.swift` |
| Everything else | Single column held to a reading width (`readablePage()`) | People, You, someone's page, a photo, Lately, Past snapshots, the snapshot composer |

`TwoPages` puts the join on the device's fold. It asks the system where the fold is (`GeometryProxy.reservedRegions(kind: .division)`, iOS 27.1) and falls back to the middle of the view on anything without one. With the phone opened flat the two pages meet on the fold's centre line; with it partly open the system marks the fold "active" and the pages keep clear of its whole width.

### Checked on the iPhone Duo simulator (2026-11-12, Xcode 27.2, iOS 27.2)

Every screen in the screenshot tour was looked at folded and unfolded, plus Home partly open.

- **The side strip.** In both poses the system draws the clock, the tabs, the back button and a screen's toolbar buttons in a strip down the right edge. The mock-ups drew the unfolded tabs on the left; the system's placement is kept, since the back button and the status items live in the same strip.
- **Buttons in the strip.** Home's Letters and Share, and You's Lately and Settings, are real toolbar items whenever the strip exists and leave the page header (`readsSideStrip()` in `Theme.swift` reads `toolbarVerticalEdge` once, around the tab view, and publishes it as `\.sideStrip`; `kitchenTableRoot(title:sideStrip:)` keeps the bar, without a title, so the system has somewhere to take them from). On every other iPhone the headers are unchanged. People keeps the same empty bar row so the three tab roots start at the same height.
- **Read the strip at the top, not per screen.** Inside a navigation stack `toolbarVerticalEdge` flickers to nil while the phone is being folded or unfolded and can settle there, which dropped the buttons back into the page until relaunch. Around the tab view it holds steady. Folding, half-opening and refolding with the app running was checked on Home, People, You and Letters.
- **The join.** The strip takes about 84 points from the right edge only, so the left page is the full left half of the display and the right page is narrower.

Working with the simulator:

- The Duo needs its own runtime (`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`) and has two displays: `xcrun simctl io <id> screenshot --display=1` is the outer screen, `--display=3` the inner one.
- Folding is done with the Closed / Partially Open / Open buttons in the Device Hub window (Xcode's simulator app); there is no `simctl` command for it.
- XCTest screenshots of the inner display come out black. `ScreenshotTourUITests` therefore prints `TOUR-SNAP <name>` and pauses at each stop when `CONNECTCHA_TOUR_SIGNAL=1`, so a script can take the picture with `simctl`.
- The tour copes with the strip (back button and tabs are outside the navigation bar and tab bar there). The scenario tests still assume an ordinary iPhone and are run on one.
