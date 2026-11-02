import SwiftUI

/// The five tabs from spec 8.5. Placeholders until their milestones.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                PlaceholderScreen(title: "Home", detail: "Stories and your feed will appear here.")
            }
            Tab("People", systemImage: "person.2.fill") {
                PlaceholderScreen(title: "People", detail: "People you know, follow requests and invites.")
            }
            Tab("Create", systemImage: "plus.circle.fill") {
                PlaceholderScreen(title: "Create", detail: "New post or story.")
            }
            Tab("Inbox", systemImage: "bubble.left.and.bubble.right.fill") {
                PlaceholderScreen(title: "Inbox", detail: "Messages.")
            }
            Tab("Profile", systemImage: "person.crop.circle.fill") {
                PlaceholderScreen(title: "Profile", detail: "Your profile and settings.")
            }
        }
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(detail)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}
