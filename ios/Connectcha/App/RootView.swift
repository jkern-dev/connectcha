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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CONNECTCHA_START_TAB"], let tab = AppTab(rawValue: raw) { return tab }
        #endif
        return .home
    }()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeTab()
            }
            Tab("People", systemImage: "person.2.fill", value: AppTab.people) {
                PeopleTab()
            }
            .badge(model.unread.pendingRequests)
            Tab("Create", systemImage: "plus.circle.fill", value: AppTab.create) {
                CreateTab(onPublished: { selection = .home })
            }
            Tab("Inbox", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.inbox) {
                PlaceholderScreen(title: "Inbox", detail: "Messages.")
            }
            .badge(model.unread.unreadConversations)
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                MyProfileTab()
            }
        }
        .task {
            await model.refreshUnread()
            if let id = model.userId { await ContactSync.shared.run(for: id) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Spec 4.2: matching re-runs whenever the app is opened.
            guard phase == .active, let id = model.userId else { return }
            Task {
                await ContactSync.shared.run(for: id)
                await model.refreshUnread()
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

