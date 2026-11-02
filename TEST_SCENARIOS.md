# Test scenarios (spec section 15)

How each scenario was checked. "Automated" names the test; "Simulator" means it was walked through on the local stack with two simulators as described in `DEMO.md`. A scenario is ticked only when both the automated test passes and the simulator walkthrough was done where one applies.

| # | Scenario | Status | Automated check | Simulator / manual check |
|---|---|---|---|---|
| S1 | Contact rule: can't find or request anyone not in contacts, except follow-back | ☑ | `020_following.sql`: no hash and wrong hash refused; correct hash accepted; follow-back only while the target follows  | `FollowingUITests.testMinimalProfileHiddenCountsAndNoStrangers`: as a new user whose contacts hold Josh but not Ben, Ben appears nowhere and there is no search field. The only routes to a profile are the match list, requests, your own lists and conversations. |
| S2 | No access without approval: pending or declined requester sees only the minimal profile | ☑ | `010_profiles.sql`, `030_posts.sql`, `040_stories.sql`: pending and declined see 0 posts, 0 media, 0 stories, bio hidden, minimal profile only  | Same test: Josh's profile shows name and photo only (no bio, no posts) before and while the request is pending; the button reads Requested. |
| S3 | Follow-back flow; numbers never shown | ☑ | `020_following.sql`: follow-back without a number, approval required before content, no phone data in any output (`010`, `060`)  | `FollowingUITests.testFollowBackFlow`: Ana requests Ben; Ben (who lacks her number) sees "Not in contacts", approves, is offered a follow-back and sends it; Ana sees "approved you and wants to follow you back" and approves. A phone-number regex finds nothing on any screen. |
| S4 | Follow-back limit after unfollow | ☑ | `020_following.sql`: after unfollow the follow-back request is refused; with the number it works  | Server rule proven by `020_following.sql`. On the simulator: after Ana unfollows Ben she leaves his follower list, so no screen offers a request; the profile's Request button only appears when `follow_back_eligible` or a contact hash exists (`ProfileModel.canRequest`). |
| S5 | Removed follower loses access immediately, isn't notified | ☑ | `020_following.sql`, `030_posts.sql`: removed follower sees nothing, gets no activity and no push | `FeedUITests.testRemovedFollowerLosesFeedAccess`: Priya sees Josh's hike post; Josh removes her from Profile › Followers; Priya's feed no longer contains it. |
| S6 | Deleted contact: follow continues, name changes to profile name | ☑ | (client behaviour; no server rule)  | `FollowingUITests.testDeletedContactKeepsFollowAndChangesName`: Demo tools › Delete "Dad" from Contacts; Following list then shows "Robert Kern" and the follow remains. |
| S7 | Names: saved name everywhere, never sent to the server | ☑ | `ContactMatcherTests.noNamesOnTheWire` records every request during a matching run over a fixture address book: no saved name or raw number appears in any URL, header or body; bodies are 64-char hex hashes only. `DisplayNamesTests` cover saved-name-first resolution. | `PeopleUITests.testSavedNamesAndNonUSInvite`: Dad's request shows "Dad" and "In your contacts", never "Robert Kern". Simulator screenshot 2026-11-02. |
| S8 | Non-users: numbers not kept; Invite opens Messages | ☑ | `060_privacy_surface.sql`: an unknown hash is found in no table after matching; `scripts/privacy-log-check.sh`: marker hash absent from every container log and table (PASS 2026-11-02). | Invite opens Messages on a phone; on the simulator a share sheet with the same text (D-12). Checked on simulator 2026-11-02. |
| S9 | Non-US invite shows country-code message, no text | ☑ | `ContactMatcherTests.invites`: non-US contacts carry no number to text. | `PeopleUITests.testSavedNamesAndNonUSInvite`: tapping Invite on Lucía (+34) shows "Not available yet" with the country-code message and no composer. |
| S10 | Non-US number can't sign up | ☑ | `001_auth_us_only.sql` (hook refuses UK, Spanish and 10-digit numbers); `PhoneNormalizerTests` (non-US shapes detected) | `SignUpFlowUITests.testNonUSNumberIsRefusedBeforeAnyCode`: a non-US shape never enables "Text me a code" and shows "That doesn't look like a US phone number". Server side on 2026-10-31: `POST /auth/v1/otp` for `+447700900123` answered "Only US phone numbers can sign up right now." and created no user row. |
| S11 | Likes: viewers see a count, poster sees who | ☑ | `030_posts.sql`: viewers see count and only their own like row; poster lists likers; likes never push | `FeedUITests.testLikesCountForViewersNamesForPoster`: Josh taps "4 likes" and sees Mom and Ana Silva in "Liked by"; Mom sees "4 likes" as plain text and tapping opens nothing. |
| S12 | Responses are private to the pair, with a post preview | ☑ | `050_messaging.sql`: response opens the pair's conversation with a post preview; third follower sees nothing | `MessagingUITests.testResponseIsPrivateToThePair`: Dad taps "Message Linda" under Mom's post and sends; Dad's and Mom's inboxes show the conversation with a post preview; Josh, who also follows Mom, has no trace of it. |
| S13 | Message limits when neither follows the other | ☑ | `050_messaging.sql`: with no follow either way, conversation readable, sending refused for both; a follow restores it | `MessagingUITests.testReadOnlyWhenNoFollowRemains`: Ana unfollows Josh and removes him; the Ana–Josh conversation is marked Read only, old messages remain, the composer is gone for both sides. |
| S14 | Stories expire for followers after 24 h, stay in archive | ☑ | `040_stories.sql`: active story visible to followers, hidden after expiry, kept in the author's archive | `StoriesUITests.testExpiredStoryOnlyInArchiveAndSeenBy`: Priya's tray plays only Josh's active story; Josh's archive lists both with one marked active and "Seen by 2" names Mom and Priya. `testPendingRequesterSeesNoStories`: a pending requester's tray shows nobody's stories. `testTrayOrderAndViewerReaction`: own story first (A3), viewer under the saved name, ❤️ reaction sent. |
| S15 | Empty state shows requests and prompts, no filler | ☑ | `FeedTests` (marker logic); `PostPipelineIntegrationTests` (publish round trip) | `FeedUITests.testEmptyFeedShowsRequestsAndPromptsOnly`: new user Nia requests Josh, Home shows "Waiting for approval: Josh Kern", Find people, Make your first post, and no post cards. Screenshot 2026-11-02. |
| S16 | Hidden lists and counts | ☑ | `020_following.sql`, `010_profiles.sql`: follows readable only for own edges; another profile carries no counts  | Same test as S2: another person's profile has no follower/following counts or lists; only your own profile tab shows them. |
| S17 | Denied contacts access: can still post, approve, follow back | ☑ | — | `PeopleUITests.testDeniedContactsStillAllowsApproving`: after denying, the People tab explains access is off, shows no "People you know", and Dad's request still has Approve/Decline; the Create tab stays enabled. |

## Notification table (spec 10)

| Event | Push | In-app | Status | How checked |
|---|---|---|---|---|
| Someone requests to follow you | Yes | Activity, People badge | ☑ | `020_following.sql` queues one push + activity; People badge from `get_unread_counts`; banner wording in `payload_test.ts`. |
| Someone approves your request | Yes | Activity | ☑ | `020_following.sql` (activity + push row); `payload_test.ts` wording. |
| New message or response | Yes | Inbox | ☑ | `NotificationsUITests.testResponsePushShowsSavedName`: Mom's response arrives as a banner "Mom responded to your post" (saved name, no message text) and opens the conversation. Inbox badge from `get_unread_counts`. |
| Someone likes your post | No | Activity, grouped | ☑ | `030_posts.sql`: likes never queue a push; `ActivityGrouping` shows "Mom and 3 others liked your post" (seeded on Josh's hike post). |
| Someone views your story | No | Seen list only | ☑ | `040_stories.sql`: view rows visible to the author only; no push, no activity row. |
| Someone you follow posts | Only with bell | Feed | ☑ | `publish_post` queues `bell_post` only for followers with a bell; `send-push` honours the bells category; bell off by default (`get_profile.relationship.bell_on`). |
| Someone you follow adds a story | Only with bell | Story tray | ☑ | `create_story` queues `bell_story` for bell holders only. |
| A contact joins | No | In-app prompt | ☑ | `ContactMatcherTests.newlyJoined`; People tab banner "X is now on here"; no push path exists for it. |

## Core rules (plan 3.6)

| Rule | Status | Automated check |
|---|---|---|
| Nobody sees posts or stories without approval | ☑ | `030_posts.sql`, `040_stories.sql`; `PostPipelineIntegrationTests` (a stranger's get-media-urls returns nothing for a published post's media) |
| Contacts are the only discovery route | ☑ | `020_following.sql` (hash proof or follow-back), `010_profiles.sql` (profiles not enumerable, D-05) |
| Phone numbers are never shown | ☑ | `000_schema.sql`, `010_profiles.sql`, `060_privacy_surface.sql` (only three functions touch phone_hash, all comparing a caller-supplied value) |
| Saved contact names never leave the device | ☑ | `ContactMatcherTests.noNamesOnTheWire` (URLProtocol recording of every request); the networking layer accepts hashes only (`ContactMatcher.Lookup`), never a `CNContact` or `LocalContact` |
| Non-users' numbers are never kept | ☑ | `060_privacy_surface.sql` (match_contacts is read-only; submitted hash found nowhere) |
| No follower lists or counts for others | ☑ | `020_following.sql`, `010_profiles.sql` |
| Only the poster sees who liked | ☑ | `030_posts.sql` |
| Responses private; messaging stops without a follow | ☑ | `050_messaging.sql` |
| Non-US numbers can't sign up | ☑ | `001_auth_us_only.sql` |
