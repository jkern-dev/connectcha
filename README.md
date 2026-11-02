# Connectcha

A photo and video sharing app for friends and family where people can only find each other through their phone contacts. iOS first.

- `PRODUCT_SPEC.md` says what it does.
- `IMPLEMENTATION_PLAN.md` says how it is built.
- `DEMO.md` walks through the prototype on two simulators (`make demo`).
- `TEST_SCENARIOS.md` says how each of the 17 scenarios was checked.
- `DECISIONS.md` records every choice the spec and plan left open; `OPEN_QUESTIONS.md` lists the ones only the owner can settle.
- `OPERATIONS.md` is the runbook (what exists, hosted setup, what M10 adds); `REFINEMENT_LOG.md` records the polish passes.

## Layout

```
ios/         SwiftUI app, Notification Service Extension, tests (XcodeGen project.yml)
supabase/    config, migrations, seeds, pgTAP tests, Edge Functions
web/         static invite page
scripts/     demo, seeding and helper scripts
Makefile     one place for every command (`make help`)
```

## Set up a Mac from scratch

Everything runs locally. No hosted accounts are needed.

1. Install Xcode 26 from the App Store and open it once to accept the licence and install the iOS 26 simulator runtime.
2. Install Homebrew from <https://brew.sh> if you don't have it.
3. Install the tools:

   ```sh
   brew install --cask docker          # Docker Desktop; open it once and let it start
   brew install supabase/tap/supabase xcodegen xcbeautify deno ffmpeg
   ```

4. Clone the repository and start the stack:

   ```sh
   git clone https://github.com/jkern-dev/connectcha.git
   cd connectcha
   make up            # starts Postgres, Auth, Storage and Edge Functions in Docker
   make reset         # applies migrations, seeds the demo people, uploads demo media
   make ios-build     # generates the Xcode project and builds the app
   ```

5. For the full two-simulator demo, follow `DEMO.md` (`make demo`).

## Everyday commands

| Command | What it does |
|---|---|
| `make up` / `make down` | Start or stop the local Supabase stack |
| `make reset` | Rebuild the database from migrations and seeds, re-upload demo media |
| `make test-db` | Run the pgTAP access-rule suite in `supabase/tests` |
| `make test-functions` | Run the Edge Function tests |
| `make ios-test` | Run the iOS unit and integration tests on the "Connectcha A" simulator (stack must be up) |
| `make ios-ui-test` | Reset demo data, then run the scenario UI tests (about 15 minutes) |
| `make test` | DB, function and iOS unit tests |
| `make privacy-check` | Prove a submitted contact hash reaches no log or table |
| `make ios-project` | Regenerate `ios/Connectcha.xcodeproj` from `ios/project.yml` |
| `make demo` | Start everything and launch two signed-in simulators |
| `supabase status` | Show local URLs and keys; Studio is at <http://127.0.0.1:54323> |

## Signing in locally

Phone sign-in uses Supabase's fixed-code test numbers, so no text message is sent. Every demo number uses the code `123456`:

| Person | Number |
|---|---|
| Josh Kern | +1 555 000 0001 |
| Linda Kern (Mom) | +1 555 000 0002 |
| Robert Kern (Dad) | +1 555 000 0003 |
| Ana Silva | +1 555 000 0004 |
| Ben Carter | +1 555 000 0005 |
| Priya Nair | +1 555 000 0006 |
| Sam Lee | +1 555 000 0007 |
| Fresh sign-up (no profile yet) | +1 555 000 0008 and 0009 |

Non-US numbers are refused by the server (`supabase/migrations/20261031000200_auth_us_only.sql`).

## Demo launch switches (debug builds only)

Environment variables the demo script passes to the simulator (see `DECISIONS.md` D-11):

| Variable | Effect |
|---|---|
| `CONNECTCHA_DEMO=1` | Seeds the signed-in persona's contacts into the simulator's Contacts |
| `CONNECTCHA_AUTO_SIGNIN=15550000001` | Signs in with that test number and the fixed code |
| `CONNECTCHA_START_TAB=people` | Opens on a tab: `home`, `people`, `create`, `inbox`, `profile` |
| launch argument `-reset-session` | Signs out first |

Example: `SIMCTL_CHILD_CONNECTCHA_DEMO=1 SIMCTL_CHILD_CONNECTCHA_AUTO_SIGNIN=15550000004 xcrun simctl launch <udid> com.connectcha.app`

## Privacy checks

- `make test-db` proves the access rules (plan 3.6) in Postgres.
- `scripts/privacy-log-check.sh` submits a marker hash through the real API and confirms it appears in no container log and no table.
- The iOS test `ContactMatcherTests.noNamesOnTheWire` records every request made during a contact-matching run and asserts no saved name or raw number is in any of them.

## Opening the project in Xcode

```sh
make ios-project
open ios/Connectcha.xcodeproj
```

Choose the `Connectcha` scheme and a simulator. The scheme sets `CONNECTCHA_DEMO=1`, which turns on the demo contact seeding described in `DECISIONS.md` D-10. The app reads the local Supabase URL and anon key from `ios/Config/Local.xcconfig`; run `make ios-config` to regenerate it if your local keys differ.

## Where the rules live

The access rules in plan section 3.6 are enforced in Postgres (row-level security and `SECURITY DEFINER` functions under `supabase/migrations`) and proven by the pgTAP suite under `supabase/tests`. Keep that suite green; every milestone adds to it.
