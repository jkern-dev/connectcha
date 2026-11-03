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

/// Three tabs (DESIGN_DIRECTION.md): Home, People, You. Share and Letters live
/// in Home's top bar; Lately and Settings in You's.
enum AppTab: String, Hashable {
    case home, people, you

    /// Accepts the older names too (`profile`, and `inbox`/`create`, which
    /// open Home with Letters pushed or the Share sheet up).
    init?(launchName: String) {
        switch launchName {
        case "home", "inbox", "create": self = .home
        case "people": self = .people
        case "you", "profile": self = .you
        default: return nil
        }
    }
}

/// What Home should do straight after launch (debug launches and deep links).
enum HomeStart: Equatable { case none, letters, share }

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab
    private let homeStart: HomeStart

    init() {
        var tab = AppTab.home
        var start = HomeStart.none
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CONNECTCHA_START_TAB"] {
            if let t = AppTab(launchName: raw) { tab = t }
            if raw == "inbox" { start = .letters }
            if raw == "create" { start = .share }
        }
        #endif
        _selection = State(initialValue: tab)
        homeStart = start
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTab(start: homeStart)
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                PeopleTab()
            }
            .badge(model.unread.pendingRequests)
            Tab("You", systemImage: "person", value: AppTab.you) {
                YouTab()
            }
        }
        .task {
            await model.refreshUnread()
            if let id = model.userId { await ContactSync.shared.run(for: id) }
        }
        .onChange(of: NotificationManager.shared.pendingDeepLink) { _, link in
            // Tab-level routing; Home handles its own routes once visible.
            switch link {
            case .people: selection = .people; NotificationManager.shared.pendingDeepLink = nil
            case .post, .profile, .conversation, .home: selection = .home
            case nil: break
            }
        }
        .task { await DebugPushPoller.shared.startIfEnabled() }
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
