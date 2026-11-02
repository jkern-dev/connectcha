# Open questions for the owner

Choices only the owner can make. Each has a sensible default already built in, so nothing blocks the demo.

| # | Question | Default used in the build | Recommendation |
|---|---|---|---|
| Q1 | **Final app name and bundle identifier.** "Connectcha" is unchecked for trademark and App Store conflicts (spec 13.2, plan R-I). | Name "Connectcha", bundle ID `com.connectcha.app`, App Group `group.com.connectcha.shared`. | Decide before the first TestFlight build (M10). Renaming before then is a find-and-replace in `ios/project.yml` and two entitlement files. |
| Q2 | **Support email address** (spec 11, plan O7). | `support@connectcha.example` in `ios/Config/Local.xcconfig`. | Create a dedicated address (for example a Gmail alias) and put it in the xcconfig; it appears in Settings and in the invite page. |
| Q3 | **Privacy policy and terms URLs** (plan O6). | The invite site hosts placeholder `privacy.html` and `terms.html` with the plain-language points the plan lists. They are drafts, not legal advice. | Have a lawyer or a reputable generator review them before TestFlight. The sign-in screen already links to them. |
| Q4 | **Apple Developer Program** (plan O5). Needed for real push notifications, Xcode Cloud and TestFlight. | Push is built end to end and verified with simulator-delivered notifications; the simulator registers a `sim:` token. iOS CI runs on GitHub's macOS runners instead of Xcode Cloud. | Enrol as an individual when ready for M8 on a real phone; add the APNs `.p8` key to the `send-push` function's secrets (see OPERATIONS.md). |
| Q5 | **Hosted accounts: Supabase, Twilio Verify, Cloudflare R2 and Pages** (plan O2 to O4). | Everything runs locally. Media uses the S3 protocol against local Supabase Storage. | Create them when the first real phones need to connect (plan 6.1). The Edge Functions take the bucket endpoint and keys from environment variables, so pointing at R2 is configuration. |
| Q6 | **GitHub Actions macOS minutes.** The iOS workflow runs on `macos-26`, which costs 10x minutes on a private repository. | The workflow runs on pushes that touch `ios/` and can be triggered by hand. | Keep it until Xcode Cloud exists, or restrict it to `workflow_dispatch` if minutes run low. |
| Q7 | **Location search provider.** The plan picks Apple MapKit local search (G4). MapKit search works on the simulator without an API key but needs network access. | MapKit `MKLocalSearch`, no location permission requested. | No action unless you want a different provider. |
| Q8 | **Reviewer test account number.** | `+1 555 000 0100`, fixed code `123456`, in `config.toml` for local only. | Choose a real test number and code in the hosted Supabase Auth settings before Beta App Review; rotate it afterwards (OPERATIONS.md). |
