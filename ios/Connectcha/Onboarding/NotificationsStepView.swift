import SwiftUI

/// Spec 9.1 step 7: notifications permission, asked last.
struct NotificationsStepView: View {
    var onDone: () -> Void
    @State private var asking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                    .padding(.top, Spacing.l)
                ScreenHeader(
                    title: "Know when something happens",
                    subtitle: "Connectcha can tell you when someone wants to follow you, approves you, or sends you a message."
                )
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label("Follow requests and approvals", systemImage: "person.badge.plus")
                    Label("Messages and responses to your posts", systemImage: "bubble.left")
                    Label("New posts from people whose bell you turn on", systemImage: "bell")
                    Label("Never for likes, and never for marketing", systemImage: "hand.raised")
                }
                .font(.body)
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
