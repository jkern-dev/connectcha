import SwiftUI

/// Spec 9.1 step 7: notifications permission, asked last.
struct NotificationsStepView: View {
    var onDone: () -> Void
    @State private var asking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader(
                    title: "Hear from them",
                    subtitle: "Connectcha can tell you when someone asks to see your photos, lets you in, or writes you a letter."
                )
                .padding(.top, Spacing.l)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label("Someone asks to see your photos, or lets you in", systemImage: "person.badge.plus")
                    Label("Letters and write-backs to your photos", systemImage: "envelope")
                    Label("New photos from people you ask to hear from", systemImage: "sun.max")
                    Label("Never for lovelies, and never for marketing", systemImage: "hand.raised")
                }
                .font(.body)
                .foregroundStyle(Palette.body)
                Button {
                    asking = true
                    Task {
                        _ = await NotificationManager.shared.requestAuthorization()
                        asking = false
                        onDone()
                    }
                } label: {
                    if asking { ProgressView().tint(.white) } else { Text("Turn on notifications") }
                }
                .buttonStyle(.primary)
                .disabled(asking)
                Button("Not now") { onDone() }
                    .buttonStyle(.secondary)
                Text("You can change this any time in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}
