import SwiftUI

/// "You": your own page (spec 8.2). The follower and following lists and the
/// counts only you can see, your photos as a filmstrip, past snapshots, and
/// the way into Lately and Settings.
struct YouTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: ProfilePage?
    @State private var showEdit = false
    @State private var addingSnapshot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header
                    if let me = model.me {
                        identity(me)
                        snapshotCard
                        photos
                        rows(me)
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .kitchenTableRoot(title: "You")
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showEdit) {
                EditProfileView()
            }
            .sheet(isPresented: $addingSnapshot) {
                ShareComposerSheet(initialKind: .snapshot, onPublished: { Task { await load() } })
            }
            .appDestinations()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("You")
                .font(.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink(value: LatelyRoute()) {
                Image(systemName: "clock")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Lately")
            .accessibilityHint("What people did with your photos")
            NavigationLink(value: SettingsRoute()) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.s)
    }

    private func identity(_ me: Me) -> some View {
        AdaptiveStack(alignment: .leading, spacing: Spacing.m) {
            AvatarView(profile: me.profile, size: 80, storyRing: page?.hasActiveStory ?? false)
            VStack(alignment: .leading, spacing: 4) {
                Text(me.profile.profileName)
                    .font(.serif(.title2, weight: .bold))
                    .foregroundStyle(Palette.ink)
                if !me.bio.isEmpty {
                    Text(me.bio).captionSerif().fixedSize(horizontal: false, vertical: true)
                }
                Button("Change your photo or words") { showEdit = true }
                    .buttonStyle(.link)
                    .accessibilityHint("Edits your name, photo and the few words under it")
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }

    @ViewBuilder
    private var snapshotCard: some View {
        if page?.hasActiveStory == true {
            NavigationLink(value: ArchiveRoute()) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "sun.horizon").font(.title3).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your snapshot is up").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("Gone tomorrow. Tap to see who looked.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { addingSnapshot = true } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.quietPill)
                    .accessibilityLabel("Add another snapshot")
                }
                .card()
            }
            .buttonStyle(.cardPress)
            .padding(.horizontal, Spacing.gutter)
        } else {
            Button { addingSnapshot = true } label: {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add a snapshot").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("A photo or short video for today. Gone tomorrow.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
                .card()
            }
            .buttonStyle(.cardPress)
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder
    private var photos: some View {
        let items = page?.posts ?? []
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Your photos", note: items.isEmpty ? nil : "what your circle sees")
                .padding(.horizontal, Spacing.gutter)
            if items.isEmpty {
                Text("Nothing on the table yet. Share a photo from Home.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .padding(.horizontal, Spacing.gutter)
            } else if typeSize.isAccessibilitySize {
                VStack(spacing: Spacing.m) {
                    ForEach(items) { item in FilmstripItem(item: item, authorName: "you", width: nil) }
                }
                .padding(.horizontal, Spacing.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in FilmstripItem(item: item, authorName: "you", width: 150) }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func rows(_ me: Me) -> some View {
        VStack(spacing: 0) {
            NavRow(title: "Past snapshots", subtitle: "Only you can see the ones that have gone", value: ArchiveRoute())
            CardDivider()
            NavRow(title: "People who follow you", subtitle: countWords(me.followerCount, "person", "people"), value: ConnectionsRoute.followers)
            CardDivider()
            NavRow(title: "People you follow", subtitle: countWords(me.followingCount, "person", "people"), value: ConnectionsRoute.following)
            if me.pendingRequestCount > 0 {
                CardDivider()
                NavRow(title: "Waiting for your yes", subtitle: countWords(me.pendingRequestCount, "request", "requests"), value: RequestsRoute())
            }
            CardDivider()
            NavRow(title: "Your number and privacy", subtitle: "Notifications, help, leaving", value: SettingsRoute())
        }
        .card(padding: 0)
        .padding(.horizontal, Spacing.gutter)
    }

    private func countWords(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    private func load() async {
        await model.refreshMe()
        if let id = model.userId {
            page = try? await API.shared.rpc("get_profile", ProfileModel.GetParams(pUserId: id, pPhoneHash: nil))
        }
    }
}

/// A row inside a card that pushes a destination.
struct NavRow<Value: Hashable>: View {
    let title: String
    var subtitle: String?
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

nonisolated enum ConnectionsRoute: Hashable, Sendable { case followers, following }
nonisolated struct ArchiveRoute: Hashable, Sendable {}
nonisolated struct RequestsRoute: Hashable, Sendable {}
nonisolated struct SettingsRoute: Hashable, Sendable {}
nonisolated struct LatelyRoute: Hashable, Sendable {}
nonisolated struct LettersRoute: Hashable, Sendable {}

/// Your followers or the people you follow (spec 8.2), with remove and
/// unfollow (spec 3.5).
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    let route: ConnectionsRoute
    @State private var connections = Connections(followers: [], following: [])
    @State private var pendingRemoval: Profile?
    @State private var error: String?

    private var people: [Profile] { route == .followers ? connections.followers : connections.following }
    private var title: String { route == .followers ? "People who follow you" : "People you follow" }

    var body: some View {
        List {
            if people.isEmpty {
                Text(route == .followers ? "Nobody follows you yet. When you let someone in, they'll appear here." : "You don't follow anyone yet.")
                    .foregroundStyle(Palette.muted)
            }
            ForEach(people) { person in
                NavigationLink(value: ProfileRoute(userId: person.id, phoneHash: nil)) {
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: person, size: 48)
                        VStack(alignment: .leading) {
                            Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text(DisplayNames.shared.contactsLabel(for: person.id)).font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .swipeActions {
                    Button(route == .followers ? "Remove" : "Unfollow", role: .destructive) { pendingRemoval = person }
                }
            }
            if let error { ErrorText(text: error) }
            Section {
                Text(route == .followers
                     ? "Swipe a name to take someone out of your circle. They stop seeing your photos straight away and are not told."
                     : "Swipe a name to stop following. You stop seeing their photos; they are not told.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            pendingRemoval.map { route == .followers ? "Take \($0.displayName) out of your circle?" : "Stop following \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(route == .followers ? "Remove" : "Unfollow", role: .destructive) {
                if let p = pendingRemoval { Task { await remove(p) } }
            }
        } message: {
            Text(route == .followers
                 ? "They'll immediately stop seeing your photos and snapshots. They won't be told."
                 : "You'll stop seeing their photos and snapshots.")
        }
    }

    private func load() async {
        do {
            connections = try await API.shared.rpc("get_my_connections")
        } catch {
            self.error = APIError(error).message
        }
    }

    private func remove(_ person: Profile) async {
        do {
            try await API.shared.call(route == .followers ? "remove_follower" : "unfollow", ProfileModel.UserParams(pUserId: person.id))
            await load()
            await model.refreshMe()
        } catch {
            self.error = APIError(error).message
        }
    }
}

/// Requests waiting for your yes, reached from You (People shows the same rows).
struct RequestsView: View {
    @State private var people = PeopleModel()
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                if people.data.incoming.isEmpty {
                    Text("Nobody is waiting right now.").foregroundStyle(Palette.muted).padding(.top, Spacing.l)
                }
                ForEach(people.data.incoming) { request in
                    RequestRow(request: request, people: people).card(padding: 16)
                }
            }
            .padding(Spacing.gutter)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Waiting for your yes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await people.load() }
        .followBackPrompt(people: people)
    }
}

/// Registers every navigation destination used across tabs.
struct AppDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0) }
            .navigationDestination(for: ConnectionsRoute.self) { ConnectionsView(route: $0) }
            .navigationDestination(for: RequestsRoute.self) { _ in RequestsView() }
            .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
            .navigationDestination(for: ArchiveRoute.self) { _ in StoryArchiveView() }
            .navigationDestination(for: LatelyRoute.self) { _ in ActivityView() }
            .navigationDestination(for: LettersRoute.self) { _ in LettersView() }
            .navigationDestination(for: PostRoute.self) { PostDetailView(postId: $0.postId) }
            .navigationDestination(for: ConversationRoute.self) { ConversationView(route: $0, onChange: {}) }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}
