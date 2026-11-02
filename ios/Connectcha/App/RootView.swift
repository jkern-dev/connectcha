import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingScreen()
            case .signedOut:
                SignInFlow()
            case .onboarding:
                OnboardingFlow()
            case .ready:
                MainTabView()
            }
        }
        .animation(.default, value: model.phase)
        .tint(Color.accentColor)
    }
}

private struct LoadingScreen: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                BrandMark()
                ProgressView()
            }
        }
    }
}

/// The five tabs from spec 8.5. Screens are filled in milestone by milestone.
enum AppTab: String, Hashable { case home, people, create, inbox, profile }

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CONNECTCHA_START_TAB"], let tab = AppTab(rawValue: raw) { return tab }
        #endif
        return .home
    }()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                PlaceholderScreen(title: "Home", detail: "Stories and your feed will appear here.")
            }
            Tab("People", systemImage: "person.2.fill", value: AppTab.people) {
                PeopleTab()
            }
            .badge(model.unread.pendingRequests)
            Tab("Create", systemImage: "plus.circle.fill", value: AppTab.create) {
                PlaceholderScreen(title: "Create", detail: "New post or story.")
            }
            Tab("Inbox", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.inbox) {
                PlaceholderScreen(title: "Inbox", detail: "Messages.")
            }
            .badge(model.unread.unreadConversations)
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileTabPlaceholder()
            }
        }
        .task { await model.refreshUnread() }
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

private struct ProfileTabPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    HStack(spacing: 16) {
                        AvatarView(profile: me.profile, size: 72)
                        VStack(alignment: .leading) {
                            Text(me.profileName).font(.title2.bold())
                            Text("Signed in").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

private extension Me {
    var profileName: String { profile.profileName }
}
