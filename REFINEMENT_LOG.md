# Refinement log

One entry per pass after M9. Each pass: use the app as a non-technical relative would on both simulators, note what is confusing, slow, ugly or fragile, fix it, re-run the tests and the scenario checklist, commit.

## Pass 0 (2026-11-02): state at the end of M8

Observed while building, fixed before refinement started:

- Light-mode text fields rendered black (asset colour components without a decimal point are read on a 0–255 scale). Fixed in M1.
- Contacts revoked after names were learned kept stale saved names. Now cleared (D-13).
- Media URL cache survived sign-out. Now cleared (D-19).
- Response RPCs return a receipt, not a message; the viewer showed "Something went wrong" after a reaction. Fixed (D-25).
- Reaction emoji render as a missing-glyph box in the iOS 26.3 simulator used here; bytes are correct (checked in the database) and real phones render them. Left as a known simulator quirk.
