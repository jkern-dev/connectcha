# Test scenarios (spec section 15)

How each scenario was checked. "Automated" names the test; "Simulator" means it was walked through on the local stack with two simulators as described in `DEMO.md`. A scenario is ticked only when both the automated test passes and the simulator walkthrough was done where one applies.

| # | Scenario | Status | Automated check | Simulator / manual check |
|---|---|---|---|---|
| S1 | Contact rule: can't find or request anyone not in contacts, except follow-back | ☐ | | |
| S2 | No access without approval: pending or declined requester sees only the minimal profile | ☐ | | |
| S3 | Follow-back flow; numbers never shown | ☐ | | |
| S4 | Follow-back limit after unfollow | ☐ | | |
| S5 | Removed follower loses access immediately, isn't notified | ☐ | | |
| S6 | Deleted contact: follow continues, name changes to profile name | ☐ | | |
| S7 | Names: saved name everywhere, never sent to the server | ☐ | | |
| S8 | Non-users: numbers not kept; Invite opens Messages | ☐ | | |
| S9 | Non-US invite shows country-code message, no text | ☐ | | |
| S10 | Non-US number can't sign up | ☐ | `supabase/tests/001_auth_us_only.sql` (hook refuses UK, Spanish and 10-digit numbers) | |
| S11 | Likes: viewers see a count, poster sees who | ☐ | | |
| S12 | Responses are private to the pair, with a post preview | ☐ | | |
| S13 | Message limits when neither follows the other | ☐ | | |
| S14 | Stories expire for followers after 24 h, stay in archive | ☐ | | |
| S15 | Empty state shows requests and prompts, no filler | ☐ | | |
| S16 | Hidden lists and counts | ☐ | | |
| S17 | Denied contacts access: can still post, approve, follow back | ☐ | | |

## Notification table (spec 10)

| Event | Push | In-app | Status | How checked |
|---|---|---|---|---|
| Someone requests to follow you | Yes | Activity, People badge | ☐ | |
| Someone approves your request | Yes | Activity | ☐ | |
| New message or response | Yes | Inbox | ☐ | |
| Someone likes your post | No | Activity, grouped | ☐ | |
| Someone views your story | No | Seen list only | ☐ | |
| Someone you follow posts | Only with bell | Feed | ☐ | |
| Someone you follow adds a story | Only with bell | Story tray | ☐ | |
| A contact joins | No | In-app prompt | ☐ | |

## Core rules (plan 3.6)

| Rule | Status | Automated check |
|---|---|---|
| Nobody sees posts or stories without approval | ☐ | |
| Contacts are the only discovery route | ☐ | |
| Phone numbers are never shown | ☐ (partial) | `000_schema.sql`: base table unreadable, no client relation has a phone column, `auth.users` unreadable |
| Saved contact names never leave the device | ☐ | |
| Non-users' numbers are never kept | ☐ | |
| No follower lists or counts for others | ☐ | |
| Only the poster sees who liked | ☐ | |
| Responses private; messaging stops without a follow | ☐ | |
| Non-US numbers can't sign up | ☑ | `001_auth_us_only.sql` |
