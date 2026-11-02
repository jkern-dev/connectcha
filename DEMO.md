# Connectcha demo

Everything runs on this Mac: Supabase in Docker, the app on two iPhone simulators. No accounts, no text messages. Every demo number signs in with the code `123456`.

## Start

```sh
make demo
```

That one command starts the stack, resets the database to the demo state, uploads the demo photos and videos, builds the app, boots two simulators ("Connectcha A" and "Connectcha B"), signs A in as **Josh** and B as **Ana**, serves the invite page and starts the push bridge. The first run takes a few minutes (package download, Docker images, Xcode build). Each simulator asks once for notification permission: tap **Allow**.

Useful while demoing:

| Command | What it does |
|---|---|
| `scripts/demo.sh as B ben` | Relaunch simulator B signed in as Ben (also `josh`, `mom`, `dad`, `ana`, `ben`, `priya`, `sam`, `nia`) |
| `make reset` then `scripts/demo.sh as A josh` | Put the data back to the starting state |
| `scripts/demo.sh stop` | Shut the simulators, web page and bridge down |
| `make down` | Stop Docker containers |
| `http://127.0.0.1:54323` | Supabase Studio, to look at tables |

Signing in by hand also works: sign out from Profile › Settings, type a number from the table below, then `123456`. In demo builds the simulator's Contacts are rewritten to match whoever signs in, so names and "People you know" always fit the person.

## The people

| Person | Number | Who they are in the story |
|---|---|---|
| Josh Kern | 555 000 0001 | You. Follows Mom, Dad and Ana. Followed by Mom, Ana and Priya. Dad's request is waiting. |
| Linda Kern ("Mom") | 555 000 0002 | Saved in Josh's phone as "Mom". Posts tomatoes and pie. Has an active story. |
| Robert Kern ("Dad") | 555 000 0003 | Saved as "Dad". Posted a video. Has requested to follow Josh. |
| Ana Silva | 555 000 0004 | Has Ben's number; Ben does not have hers (follow-back story). |
| Ben Carter | 555 000 0005 | Follows Priya. Nobody in Josh's contacts. |
| Priya Nair | 555 000 0006 | Follows Josh; Josh has a request out to her. |
| Sam Lee | 555 000 0007 | A stranger. Posted something nobody can see. |
| Nia Newcomer | 555 000 0008 | A brand-new user with Josh and Ana in her contacts and no follows. |

Josh's phone also holds "Uncle Mike" (not on the app) and "Lucía Fernández" (a Spanish number).

## Walkthrough, scenario by scenario

Numbers match spec section 15. A = Josh's simulator, B = Ana's unless stated.

1. **Contact rule.** On A open **People**. "People you know" lists only matched contacts (Priya, shown as *Requested*). There is no search anywhere. Ben Carter appears nowhere on Josh's phone. On B (Ana) Ben *is* listed, because Ana has his number. → You can only find people whose number you have.
2. **No access without approval.** `scripts/demo.sh as B nia`. On B, People › tap **Josh Kern** › **Request to follow**. The profile shows only his name and photo, "Requested", no posts, no bio. Home shows "Your feed is empty for now" with the pending request and prompts, nothing else (that is scenario 15 too).
3. **Follow-back.** `scripts/demo.sh as B ana`. On B, People › **Request** next to Ben Carter. Then `scripts/demo.sh as B ben`. Ben's People tab shows "Ana Silva · Not in contacts" (he lacks her number). Tap **Approve** → "Follow Ana Silva back?" → **Request to follow**. Ben still can't see her posts: Profile › Followers › Ana Silva shows *Requested* and no grid. `scripts/demo.sh as B ana`: her People tab reads "Ben Carter approved you and wants to follow you back" → **Approve**. No screen anywhere showed a phone number.
4. **Follow-back limit.** On B (Ana) Profile › Following › swipe Ben › **Unfollow**. Now `scripts/demo.sh as B ben`: Ana has left his follower list and there is no screen offering a request to her; Ben would need her number (People you know). The server refuses a follow-back request once the follow ends (`supabase/tests/020_following.sql`).
5. **Removed follower.** On A Profile › Followers › swipe **Priya Nair** › Remove. `scripts/demo.sh as B priya`: Josh's hike post is gone from her feed, and nothing in her Activity mentions it.
6. **Deleted contact.** On A Profile › Settings › Demo tools › **Delete "Dad" from Contacts**. Go back to People: the request now reads **Robert Kern · Not in contacts**, and Profile › Following still lists him. Demo tools › **Re-seed this persona's contacts** puts "Dad" back.
7. **Names.** Across A, Mom appears as "Mom" in the feed, story tray, inbox and request lists; on B (Ana) the same person is "Linda Kern" (Ana doesn't have her saved). The proof that names never leave the device is the test `ContactMatcherTests.noNamesOnTheWire`, which records every request during a matching run.
8. **Non-users.** On A People › Invite to Connectcha lists Uncle Mike and the simulator's built-in contacts. Tap **Invite** → on a simulator a share sheet with the prefilled text appears (a real phone opens Messages). `scripts/privacy-log-check.sh` proves a submitted number's hash lands in no log and no table.
9. **Non-US invite.** Same list: tap **Invite** next to **Lucía Fernández** → "Not available yet … country code isn't accepted yet", and no text composer.
10. **Non-US sign-up.** Sign out on B and try to type a UK number: the field only accepts US shapes. Server side: `curl` an OTP for `+447700900123` and the API answers "Only US phone numbers can sign up right now." (`supabase/tests/001_auth_us_only.sql`).
11. **Likes.** On A scroll Home to Josh's "Hike with the dogs": tap **4 likes** → the list names Mom, Dad, Ana Silva, Priya Nair. On B as Mom (`scripts/demo.sh as B mom`) the same post shows "4 likes" as plain text that opens nothing.
12. **Comments are private.** On B as Mom, under Josh's hike post tap **Message Josh** and send a line. Only Mom and Josh have that conversation (Inbox on A). `scripts/demo.sh as B dad`: Dad also follows Josh but his Inbox has nothing about it.
13. **Message limits.** On B as Ana, Inbox › Josh Kern: the composer works. Profile › Following › Unfollow Josh, Followers › Remove Josh. Back in Inbox the conversation is marked **Read only**; opening it shows the old messages and "You can read this conversation but not send new messages". The same on A.
14. **Stories.** On A the tray shows **Your story** first, then Mom and Ana. Open Mom's story: it plays, you can react ❤️ or reply. Profile › **Story archive** lists Josh's active story *and* the one that expired six hours ago; followers never see the expired one. Open the active one: **Seen by 2** names Mom and Priya.
15. **Empty state.** See step 2.
16. **Hidden lists.** Open any other person's profile (e.g. Mom from the feed header): no follower or following numbers anywhere. Only your own Profile tab has them.
17. **Denied contacts.** On B as Nia: iOS Settings › Apps › Connectcha › Contacts › off (or deny when first asked). People shows "Contacts access is off" with no "People you know", but the Create tab still posts and any incoming request can still be approved.

### Notifications (spec 10)

With the bridge running, each simulator gets real banners. Try: on B as Mom, respond to Josh's post → A shows **"Mom responded to your post"** (the server only knew "Linda Kern"; the saved name is swapped in on the phone, from the match map in the App Group container). Tap the banner: it opens the conversation. Likes never notify. The bell on a profile (Profile › person › **Notify me**) turns on "shared a new post" banners for that person only.

Simulator note: iOS simulators don't run Notification Service Extensions, so `scripts/push-bridge.sh` performs the same name swap the extension does on a real phone (DECISIONS D-27). If a simulator never got the permission prompt answered, `scripts/demo.sh allow A` (or `B`) answers it.

### Making things

Create › **New post**: pick from the camera roll (sample photos and a video are preloaded), add a caption and a location, share. Create › **New story**: pick a photo, add a line of text, share; it appears first in the tray with a ring.

## If something is off

- Simulators refuse to launch the app → `scripts/demo.sh stop`, then `make demo` again.
- "Something went wrong" banners → check the stack with `supabase status`; `make up` if it is down.
- The data is in a strange state after experimenting → `make reset` and relaunch the simulators (`scripts/demo.sh as A josh`, `scripts/demo.sh as B ana`).
- Emoji showing as boxes is a simulator font quirk on some iOS 26 runtimes; real phones render them.
