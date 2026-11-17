# Connectcha: Product Spec

**Status:** Agreed scope for the first working version
**Date:** 2026-10-31
**Purpose:** Defines what to build. A separate build agent will decide the architecture, build plan and implementation.

"Connectcha" is a working name. It hasn't been checked for trademark or App Store conflicts.

**Revision 2026-10-31 (implementation review).** Three changes were agreed with the owner before building started. See `IMPLEMENTATION_PLAN.md` section 1.2 for the reasons.

1. "Request all" is replaced by a checklist with nothing preselected and a single "Send requests" button (9.1 step 5, 8.5). Apple's review guideline 5.1.2(v) forbids select-all options over Contacts data.
2. The "mutual followers" hint on follow requests is removed (3.4), so 8.4 holds without exception.
3. The section 14 defaults are confirmed, with the A6 limits set.

---

## 1. Product summary

Connectcha is a photo and video sharing app, with an Instagram-style timeline and stories, for staying close to friends and family.

**The defining rule:** you can only find and request to follow someone if their phone number is in your contacts. There's no search, Explore page, suggested content or public profile, so the feed contains only people you know and have chosen to follow.

### Product principles

Use these to resolve any question this spec doesn't answer.

1. **Your contacts decide who can find you. Your approval decides who sees your posts.** Having a number never grants access by itself.
2. **Nobody sees your posts unless you approved them.** This has no exceptions.
3. **Your contacts are the only way to discover people.** Nothing else in the app may become a route to following someone, apart from the follow-back exception in 3.3.
4. **Phone numbers are never shown.** People appear by name only.
5. **No algorithm and no ads.** The feed is newest first, and the app shows only content from people you follow.
6. **There's no popularity signal.** Other people's follower counts and lists are hidden.
7. **Keep it simple and readable,** including for older relatives who aren't technical.

---

## 2. First version: audience and scope

| Area | Decision |
|---|---|
| Audience | The owner's friends and family, growing naturally through contact invites |
| Platform | iOS is the priority. Use a shared iOS and Android codebase if that doesn't delay or compromise iOS. Android follows later. No web app, apart from the invite page in 9.3. |
| Distribution | Public TestFlight link |
| Supported numbers | US (+1) numbers only |
| Scale | Hundreds of users. Keep the design simple, but photos and videos must load quickly on a normal phone connection. |
| Price | Free, with no ads, no selling of data and no payments built |

---

## 3. Accounts, identity and following

### 3.1 Identity

- A phone number is the account's identity.
- An account's username is the person's first and last name. Both are required. Names are entered by the user, aren't verified and don't have to be unique.
- There are no @handles and no shareable profile links.
- A profile photo is optional, with initials shown if there's none.

### 3.2 How names are displayed

| Situation | What's displayed |
|---|---|
| Person is in your contacts | The name you saved for them in your phone |
| Person isn't in your contacts | Their first and last name from their profile |

- This applies everywhere in the app.
- Saved contact names stay on the device and are never sent to the server.
- Phone numbers are never shown anywhere, including when requesting, following back or messaging.

### 3.3 Follow model

Following is one-way, as on Instagram, and every account is private. There are no public profiles.

**Sending a request.** You can request to follow someone in either of these cases:

1. **Their number is in your contacts.**
2. **Follow-back:** they currently follow you, because you approved their request. You don't need their number.

**Approval.** Every follow needs the recipient's approval, including follow-backs.

**Follow-back flow.** Using Ana, who has Ben's number, and Ben, who doesn't have Ana's:

1. Ana requests to follow Ben.
2. Ben approves. Approving and following back are separate actions.
3. After Ben approves, a follow-up prompt asks whether he wants to follow Ana back.
4. If he accepts, Ana gets a normal follow request, identified as a follow-back. For example: "Ben approved you and wants to follow you back."
5. Ana approves or declines. Ben can't see her posts unless she approves.

**Follow-back limits**

- It's available only after Ben has approved Ana. It isn't available while her request is pending or after he's declined it.
- If Ana stops following Ben, his right to send a follow-back ends unless he has her number. If he already follows her, that follow continues until one of them removes it.

### 3.4 Follow requests

The request screen shows:

| Sender | Name | Label | Also shown |
|---|---|---|---|
| In your contacts | The name you saved | "In your contacts" | Photo |
| Not in your contacts | Their profile name | "Not in contacts" | Photo |

- No "mutual followers" hint is shown. It would reveal part of other people's follower and following lists, which 8.4 forbids. (Revised 2026-10-31.)
- The sender's posts and stories stay hidden.
- The recipient can approve or decline.

### 3.5 Ending a follow

- **Unfollow:** you can stop following anyone at any time.
- **Remove follower:** you can remove anyone who follows you, and they aren't notified. They can send a new request later if they're eligible under 3.3.
- Access to posts and stories ends immediately in both cases.
- Deleting someone from your phone contacts doesn't affect existing follows in either direction. Their display name and label change according to 3.2 and 3.4, and any pending request you sent them stays pending.

---

## 4. Contacts and invites

### 4.1 Contacts access

- Contacts access is optional. Without it, you can't find anyone, but you can still approve requests, follow back and post. The app explains that it needs access to find people.
- If someone shares only selected contacts on iOS, only those are matched.
- There's no manual phone number entry. To add someone, save them to your phone first.

### 4.2 Matching and data handling

- Contacts are used only to find matches.
- Numbers of people who aren't on the app are discarded, with no hidden profiles of non-users and no server-side copy of anyone's address book.
- Matching re-runs whenever the app is opened.
- When someone in your contacts newly appears, the app shows a small prompt, such as "Mom is now on here". There's no push notification.
- Contact numbers without a country code are treated as US numbers.

### 4.3 Invites

- Contacts who didn't match appear in an invite list.
- Tapping "Invite" opens the phone's messaging app with a pre-written text and invite link, which the user sends. The app never texts non-users directly.
- Non-US contacts stay in the list. Tapping "Invite" on one shows a message that their country code isn't accepted yet.

---

## 5. Timeline and posts

### 5.1 Feed

- Strictly newest first, with no algorithmic ranking.
- Contains only posts from people you follow, with no suggested content and no ads.
- Shows "You're all caught up" when you reach posts you've already seen.

### 5.2 Posts

- 1 to 10 photos or videos per post.
- Videos can be up to 60 seconds each.
- Optional caption, which can be edited after posting.
- Optional location tag, chosen by the person posting. Location is never attached automatically from the phone or photo.
- Media can't be edited after posting.
- Posts can be deleted at any time.
- Every post goes to all approved followers. There are no audience lists or per-post audiences.

### 5.3 Likes

- Like with a heart button or a double tap.
- Anyone who can see the post sees the like count.
- Only the poster can see who liked it, by tapping the count.
- There's no total like count on a profile.

### 5.4 Comments

There are no public comments. A comment is a private message to the poster.

- The input under a post reads "Message [name]", so nobody thinks they're commenting publicly.
- Posters can turn off responses for each post.
- See section 7 for how messaging works.

---

## 6. Stories

**Basics**

- Stories disappear after 24 hours and can be deleted sooner.
- They go to all approved followers.
- They can be photos or videos up to 60 seconds, and several in a row play in order.

**Story tray**

- A row at the top of Home.
- People with unseen stories come first, with the most recent first within each group. There's no ranking based on who you interact with.

**Creation tools**

- Camera and camera roll.
- Text overlays.
- Optional location tag.

**Interactions**

- A reply goes to the same one-to-one conversation with the poster, with a small preview of the story.
- A quick emoji reaction is sent as a message in that conversation. There's no story like count.
- Only the poster can see who viewed a story.
- Posters can turn off replies for each story.

**Keeping stories**

- Expired stories go to a private archive that only the owner can see.
- You can save your own stories to your phone.
- The app doesn't try to detect or block screenshots.

---

## 7. Messaging

Messaging exists to support responses to posts and stories. It isn't meant to be a standalone chat product.

- **Conversations:** each pair of people has one ongoing conversation. Responses appear there with a small preview of the post or story.
- **Starting one:** a conversation can start only from a response to a post or story. After that, either person can continue it, including a poster who doesn't follow the person who responded.
- **Content:** text and emoji only.
- **Who can send:** people can send messages only while at least one of them follows the other. If that ends, the conversation stays readable, but no new messages can be sent.
- **Deleted posts:** the preview changes to "Post no longer available".
- **Privacy:** messages are encrypted in transit and on the server, but aren't end-to-end encrypted. The privacy policy must say this clearly.

---

## 8. Profiles and navigation

### 8.1 Profile as seen by an approved follower

- Name, according to 3.2
- Profile photo and an optional short bio
- A grid of posts
- A story ring on the photo when there's an active story
- A "Notify me" bell and an "Unfollow" option

### 8.2 Your own profile

Everything in 8.1, except the bell and "Unfollow", plus:

- Your follower and following lists and counts, visible only to you
- Edit profile
- Story archive
- Settings
- Follow requests
- Remove follower

### 8.3 Minimal profile

This is what you see when you open the profile of someone you don't follow.

- Only their name and photo, with no posts, stories or bio.
- A "Request to follow" button appears only if you're eligible under 3.3.

### 8.4 Privacy of lists and counts

Nobody can see another person's follower or following lists or counts. This includes that person's own followers.

### 8.5 Navigation

| Tab | Contents |
|---|---|
| **Home** | Story tray and feed. A heart icon at the top opens the activity list. |
| **People** | "People you know", follow requests and invites. Shows a badge for new follow requests. |
| **Create (+)** | New post or story |
| **Inbox** | Messages. Shows a badge for unread conversations. |
| **Profile** | Your profile and settings |

"People you know" lists contacts who are on the app and whom you don't follow. It's the only discovery surface in the app. Each person has their own "Request" button. There's no select-all or "Request all" option anywhere in the app (see 9.1 step 5).

### 8.6 Look and feel

- Warm, simple and uncluttered.
- Large, readable text and clear labels, with older relatives in mind.
- Light and dark mode, following the phone's setting.
- Detailed visual design is left to the build stage.

---

## 9. Onboarding and sign-in

### 9.1 Signup steps

1. **Phone number and text code.** US numbers only. Terms and privacy policy are linked here.
2. **First and last name.** Both required.
3. **Profile photo.** Optional, but encouraged.
4. **Contacts access.** A screen first explains why it's needed, and promises that saved names stay on the phone and non-users' numbers aren't kept.
5. **People you know.** Matched contacts shown as a checklist with nothing preselected. The user ticks the people they want and taps a single "Send requests" button, which shows the count, such as "Send 4 requests". There's no "Request all" or select-all option. (Revised 2026-10-31: Apple's App Store Review Guideline 5.1.2(v) forbids a Select All option or default selection over Contacts data.)
6. **Invite people.** Contacts who aren't on the app, with an easy skip.
7. **Notifications permission.** Asked last.

### 9.2 Empty feed

The feed shows pending requests, prompts to invite people or make a first post, and an explanation that it fills up as people approve you. It never shows filler content.

### 9.3 Invite page

The invite link opens a simple web page that detects the phone type.

- **iPhone:** clear step-by-step instructions, including installing TestFlight, then the public TestFlight link. Instructions need to suit less technical relatives.
- **Android:** a "Coming soon" message. It collects no information.

There are no invite codes. Anyone with the link and a US number can sign up.

### 9.4 Signing in

- Users stay logged in indefinitely on a device.
- A new device needs a new text code.

---

## 10. Notifications

| Event | Push notification | In-app |
|---|---|---|
| Someone requests to follow you | Yes | Activity list, People tab badge |
| Someone approves your request | Yes | Activity list |
| New message or response to a post or story | Yes | Inbox |
| Someone likes your post | No | Activity list, grouped, such as "Mom and 3 others" |
| Someone views your story | No | Story's seen list only |
| Someone you follow posts | Only if you've turned on their bell | Feed |
| Someone you follow adds a story | Only if you've turned on their bell | Story tray |
| A contact joins | No | In-app prompt |

- **"Notify me" bell:** set per person on their profile, and off by default.
- **Settings:** on/off for each category: requests, messages, likes, and people you've turned on.
- **Not in this build:** re-engagement notifications, such as "You haven't posted in a while". These may be considered later. Marketing pushes aren't included either.

---

## 11. Data and privacy

- **Usage data:** collect only what's critical to operating the app. That means the data its features need, plus error and crash logs needed to keep it running. Logs must not include post content, messages or contact details.
- **No analytics or ad tracking:** no product analytics, and no third-party advertising trackers.
- **Content retention:** posts and messages are kept until deleted by the user, with no time limit. Expired stories stay in the owner's private archive.
- **Support:** the app includes a contact email, which testers can use for problems and account deletion requests. The owner handles these manually.

---

## 12. Out of scope for this version

**Content and creation**

- Reels and Explore
- Hashtags, reposts, and sharing to another account
- Tagging or mentioning people
- Public comments
- Story filters, AR effects, music, polls, drawing, stickers and mentions
- Story Highlights

**Audiences and messaging**

- Close friends lists or per-post audiences
- Starting a message without a post or story
- Group chats, and photos or voice notes in messages
- Read receipts and typing indicators
- End-to-end encryption

**Business and measurement**

- Ads and payments. A subscription or paid family storage may be considered after the beta, but ads conflict with the product's principles.
- Success metrics and product analytics
- Re-engagement notifications

**Platforms**

- Web app
- Android, unless it comes from the shared codebase described in section 2
- Numbers outside the US

---

## 13. Required before public launch

These are deliberately deferred. They aren't optional in the long term.

### 13.1 When this work must be done

Complete this list before the **earliest** of these:

- Moving to the public App Store
- Reaching 500 users
- Learning that people the owner doesn't know, even indirectly, are using the app

### 13.2 The list

| Item | Why it matters |
|---|---|
| Reporting of posts, stories, messages and accounts | Apple and Google require it for apps with user-generated content |
| Internal moderation tools | Needed to review reports, remove content and suspend accounts |
| Blocking | Required by app store rules. A block should hide each person from the other, end follows and stop messages. |
| In-app account deletion | Required by Apple. Needs a decision on what happens to a deleted user's messages. |
| Checks for known child sexual abuse material, and legally required reporting | Needs a lawyer's review |
| Minimum age and age check | 13+ was proposed. Under-13 accounts would trigger stricter rules such as COPPA. |
| Contact-matching rate limits and abuse detection | See risk R2 below |
| Number changes, lost numbers and reassigned numbers | See risk R1 below |
| Trademark and App Store name check | "Connectcha" is unverified |

### 13.3 Known risks accepted for this version

- **R1: Reassigned numbers.** Login is a text code only. If a carrier reassigns a former user's number, the new owner could log in to that account and see everything it can see, including followed accounts' posts and private messages. Their name could also appear under a saved contact name, such as "Mom", with an "In your contacts" label. Also, a user who changes numbers has no way to keep their account.
- **R2: Contact-matching abuse.** Anyone could load many numbers into their phone and learn who's on the app, along with their names and photos, or send mass requests. Approval protects posts, but not this information.
- **R3: Unwanted contact.** Without blocking, someone can only decline requests or remove a follower. Declining or removing doesn't stop them from sending another request. Problems are handled manually through the contact email.
- **R4: TestFlight review.** Apple reviews builds before external testing and may hold the app to its rules for user-generated content or contact data. If review objects to missing reporting or blocking, those items need to move forward.
- **R5: TestFlight limits.** There's a limit of 10,000 external testers, builds expire after 90 days, and invitees must install the TestFlight app first. A new build must ship at least every 90 days.

---

## 14. Assumptions to confirm

The interview didn't settle these directly. They're defaults that follow the product principles. **All seven were confirmed by the owner on 2026-10-31** and are now settled decisions.

| # | Topic | Confirmed decision |
|---|---|---|
| A1 | Declined requests | The sender isn't told and continues to see "Requested". They can cancel it and send a new one. |
| A2 | Expired story previews in messages | Show "Story no longer available", so a reply doesn't keep the story visible after it expires |
| A3 | Your own story in the tray | Appears first |
| A4 | Editing a location tag | Can be changed after posting, like a caption |
| A5 | Contacts with several numbers | Match on any of their numbers |
| A6 | Caption, bio and message lengths | Caption 1,000 characters, bio 150, message 2,000. Easy to change later. |
| A7 | Error and crash logs | Count as critical operational data under section 11 |

---

## 15. Key scenarios to verify

1. **Contact rule:** a user can't find or request anyone whose number isn't in their contacts, unless the follow-back rule applies.
2. **No access without approval:** a pending or declined requester can't see posts or stories, and sees only the minimal profile.
3. **Follow-back:** after Ben approves Ana, he's prompted to follow back. Ana must approve him before he sees her posts, and at no point does either of them see the other's number.
4. **Follow-back limit:** once Ana stops following Ben, Ben can't send a request to her unless she's in his contacts.
5. **Removed follower:** the person immediately loses access and isn't notified.
6. **Deleted contact:** an existing follow continues, and the display name changes to the person's profile name.
7. **Names:** a contact appears under the saved name everywhere in the app, and that saved name is never sent to the server.
8. **Non-users:** their numbers aren't kept after matching, and tapping "Invite" opens the user's own messaging app.
9. **Non-US invite:** tapping "Invite" on a non-US contact shows the country code message and doesn't open a text.
10. **Non-US signup:** a non-US number can't sign up.
11. **Likes:** viewers see only a count, while the poster also sees who liked the post.
12. **Comments:** a response to a post appears only in the two people's conversation, with a post preview, and never to other followers.
13. **Message limits:** when neither person follows the other, the conversation stays readable but can't receive new messages.
14. **Stories:** a story disappears from followers' view after 24 hours and stays in the owner's archive.
15. **Empty state:** a new user with no connections sees pending requests and prompts, not filler content.
16. **Hidden lists:** no one can see another person's follower or following lists or counts.
17. **Denied contacts access:** the user can still post, approve requests and follow back, but can't find anyone.
