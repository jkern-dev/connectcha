
- **D-11: Debug-only launch switches for demos and tests** (2026-11-02, M3)
- Context: Simulators can't be driven by taps from a script, and the demo needs two simulators signed in as different people with one command.
- Options considered: (a) Script sign-in through XCUITest every time: slow and fragile. (b) Environment variables honoured only in DEBUG builds: `CONNECTCHA_AUTO_SIGNIN=<test number>` signs in with the fixed code, `CONNECTCHA_START_TAB=<tab>` opens a tab, `CONNECTCHA_DEMO=1` turns on contact seeding; a `-reset-session` argument signs out first.
- Chosen: (b). Release builds compile none of it out of `#if DEBUG`.
- Reversibility: Trivial; delete the blocks.

- **D-12: Invite on a simulator uses a share sheet** (2026-11-02, M3)
- Context: Spec 4.3 says Invite opens the phone's Messages app. The simulator has no Messages, so `MFMessageComposeViewController.canSendText()` is false.
- Options considered: (a) Show an error on simulators. (b) Fall back to the system share sheet carrying the same prefilled text, so the flow can still be demonstrated; real phones always get Messages.
- Chosen: (b). The non-US branch is unaffected: it shows the country-code message and opens nothing.
- Reversibility: Trivial.

- **D-13: Revoking contacts access drops saved names** (2026-11-02, M3)
- Context: The spec covers deleting one contact (3.5) but not turning contacts access off after names were learned. The on-device match map would otherwise keep showing stale saved names.
- Options considered: (a) Keep the last known names: shows names the phone may no longer have. (b) When access is not readable, clear the match map and fall back to profile names until access returns.
- Chosen: (b). It matches the rule that the display name follows what is in the contacts right now.
- Reversibility: Easy; one branch in `ContactSync.run`.

- **D-14: Analytics container off, so the "privacy log check" uses docker logs** (2026-11-02, M3)
- Context: Follows D-08. The plan's M3 check searched Supabase Logs Explorer for a submitted hash.
- Chosen: `scripts/privacy-log-check.sh` submits a marker hash through the real API, then greps every local container's logs and scans every table for it. It also prints `log_statement` (expected `ddl`, so statements with parameters are never logged).
- Reversibility: Trivial.
