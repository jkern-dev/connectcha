import SwiftUI

/// Spec 8.2: your own profile, with the follower and following lists and
/// counts that only you can see, edit profile, story archive, settings and
/// follow requests.
struct MyProfileTab: View {
    @Environment(AppModel.self) private var model
    @State private var page: ProfilePage?
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let me = model.me {
                    VStack(spacing: Spacing.l) {
                        VStack(spacing: Spacing.s) {
                            AvatarView(profile: me.profile, size: 120, storyRing: page?.hasActiveStory ?? false)
                            Text(me.profile.profileName).font(.title.bold())
                            if !me.bio.isEmpty {
                                Text(me.bio).multilineTextAlignment(.center).padding(.horizontal, Spacing.l)
                            }
                        }
                        HStack(spacing: Spacing.m) {
                            NavigationLink(value: ConnectionsRoute.followers) {
                                CountTile(count: me.followerCount, label: "Followers")
                            }
                            NavigationLink(value: ConnectionsRoute.following) {
                                CountTile(count: me.followingCount, label: "Following")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.m)
                        .accessibilityElement(children: .contain)

                        HStack(spacing: Spacing.s) {
                            Button("Edit profile", systemImage: "pencil") { showEdit = true }.buttonStyle(.quietPill)
                            NavigationLink(value: ArchiveRoute()) {
                                Label("Story archive", systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.quietPill)
                        }
                        if me.pendingRequestCount > 0 {
                            NavigationLink(value: RequestsRoute()) {
                                Label("\(me.pendingRequestCount) follow request\(me.pendingRequestCount == 1 ? "" : "s")", systemImage: "person.badge.clock")
                            }
                            .buttonStyle(.quietPill)
                        }
                        PostsGrid(items: page?.posts ?? [], authorName: "you")
                    }
                    .padding(.vertical, Spacing.l)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: SettingsRoute()) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showEdit) {
                EditProfileView()
            }
            .appDestinations()
        }
    }

    private func load() async {
        await model.refreshMe()
        if let id = model.userId {
            page = try? await API.shared.rpc("get_profile", ProfileModel.GetParams(pUserId: id, pPhoneHash: nil))
        }
    }
}

private struct CountTile: View {
    let count: Int
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2.bold())
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label.lowercased())")
        .accessibilityHint("Shows the list")
    }
}

nonisolated enum ConnectionsRoute: Hashable, Sendable { case followers, following }
nonisolated struct ArchiveRoute: Hashable, Sendable {}
nonisolated struct RequestsRoute: Hashable, Sendable {}
nonisolated struct SettingsRoute: Hashable, Sendable {}

/// Your followers or the people you follow (spec 8.2), with remove and
/// unfollow (spec 3.5).
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    let route: ConnectionsRoute
    @State private var connections = Connections(followers: [], following: [])
    @State private var pendingRemoval: Profile?
    @State private var error: String?

    private var people: [Profile] { route == .followers ? connections.followers : connections.following }

    var body: some View {
        List {
            if people.isEmpty {
                Text(route == .followers ? "Nobody follows you yet. When you approve a request, they'll appear here." : "You don't follow anyone yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(people) { person in
                NavigationLink(value: ProfileRoute(userId: person.id, phoneHash: nil)) {
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: person, size: 48)
                        VStack(alignment: .leading) {
                            Text(person.displayName).font(.headline)
                            Text(DisplayNames.shared.contactsLabel(for: person.id)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .swipeActions {
                    Button(route == .followers ? "Remove" : "Unfollow", role: .destructive) { pendingRemoval = person }
                }
            }
            if let error { ErrorText(text: error) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(route == .followers ? "Followers" : "Following")
        .task { await load() }
        .confirmationDialog(
            pendingRemoval.map { route == .followers ? "Remove \($0.displayName) as a follower?" : "Unfollow \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(route == .followers ? "Remove" : "Unfollow", role: .destructive) {
                if let p = pendingRemoval { Task { await remove(p) } }
            }
        } message: {
            Text(route == .followers
                 ? "They'll immediately stop seeing your posts and stories. They won't be told."
                 : "You'll stop seeing their posts and stories.")
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

/// Follow requests reached from the profile (the People tab shows the same rows).
struct RequestsView: View {
    @State private var people = PeopleModel()
    var body: some View {
        List {
            if people.data.incoming.isEmpty {
                Text("No follow requests right now.").foregroundStyle(.secondary)
            }
            ForEach(people.data.incoming) { request in
                RequestRow(request: request, people: people)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Follow requests")
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
            .navigationDestination(for: ArchiveRoute.self) { _ in StoryArchivePlaceholder() }
            .navigationDestination(for: PostRoute.self) { PostPlaceholder(route: $0) }
            .navigationDestination(for: ConversationRoute.self) { ConversationPlaceholder(route: $0) }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}

// Placeholders replaced in M5 to M7.
struct StoryArchivePlaceholder: View {
    var body: some View { Text("Your expired stories will appear here.").foregroundStyle(.secondary).navigationTitle("Story archive") }
}
struct PostPlaceholder: View {
    let route: PostRoute
    var body: some View { Text("Post view arrives in the next milestone.").foregroundStyle(.secondary) }
}
struct ConversationPlaceholder: View {
    let route: ConversationRoute
    var body: some View { Text("Messages arrive in a later milestone.").foregroundStyle(.secondary) }
}
