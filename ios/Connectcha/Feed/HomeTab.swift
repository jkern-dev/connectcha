import SwiftUI

/// Spec 8.5 Home: story tray and feed, heart icon for activity.
struct HomeTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed = FeedModel()
    @State private var people = PeopleModel()
    @State private var tray = StoryTrayModel()
    @State private var likersFor: Post?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Spacing.s) {
                    if !tray.groups.isEmpty || appModel.me != nil {
                        StoryTrayView(model: tray)
                    }
                    if !feed.loadedOnce {
                        ProgressView("Loading your feed…")
                            .padding(.top, 60)
                    } else if feed.posts.isEmpty {
                        EmptyFeedView(people: people)
                    } else {
                        feedList
                    }
                }
                .padding(.bottom, Spacing.l)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Connectcha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ActivityRoute()) {
                        Image(systemName: "heart")
                    }
                    .accessibilityLabel("Activity")
                }
            }
            .refreshable {
                await feed.refresh()
                await tray.load()
                await people.load()
            }
            .task {
                await feed.refresh()
                await tray.load()
                await people.load()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await feed.refresh(); await tray.load() } }
                if phase == .background { Task { await feed.markSeen() } }
            }
            .onDisappear { Task { await feed.markSeen() } }
            .sheet(item: $likersFor) { post in
                LikersView(post: post)
            }
            .onChange(of: NotificationManager.shared.pendingDeepLink) { _, link in
                guard let link else { return }
                switch link {
                case .post(let id): path.append(PostRoute(postId: id)); NotificationManager.shared.pendingDeepLink = nil
                case .profile(let id): path.append(ProfileRoute(userId: id, phoneHash: nil)); NotificationManager.shared.pendingDeepLink = nil
                case .conversation(let id): path.append(ConversationRoute(conversationId: id, otherUserId: nil)); NotificationManager.shared.pendingDeepLink = nil
                case .home: NotificationManager.shared.pendingDeepLink = nil
                case .people: break   // handled by the tab container
                }
            }
            .appDestinations()
            .feedDestinations(feed: feed)
        }
    }

    private var feedList: some View {
        let marker = FeedModel.caughtUpIndex(posts: feed.posts, seenThrough: feed.seenThrough)
        return ForEach(Array(feed.posts.enumerated()), id: \.element.id) { index, post in
            if marker == index { CaughtUpMarker() }
            PostCard(
                post: post,
                onLike: { Task { await feed.toggleLike(post) } },
                onOpenLikers: { likersFor = post },
                onOpenPost: { path.append(PostRoute(postId: post.id)) },
                onMessage: { path.append(ComposeResponseRoute(postId: post.id)) },
                onMenu: post.isMine ? { path.append(PostRoute(postId: post.id)) } : nil
            )
            .onAppear { Task { await feed.loadMoreIfNeeded(current: post) } }
            if marker == feed.posts.count, index == feed.posts.count - 1 { CaughtUpMarker() }
        }
    }
}

struct CaughtUpMarker: View {
    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Color.accentColor)
            Text("You're all caught up").font(.headline)
            Text("You've seen everything new since you were last here.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Spec 9.2: pending requests, prompts to invite or post, and why the feed is
/// empty. Never filler content.
struct EmptyFeedView: View {
    @Environment(AppModel.self) private var appModel
    let people: PeopleModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Your feed is empty for now")
                    .font(.title2.bold())
                Text("Connectcha only shows posts from people you follow. It fills up as people approve your requests.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !people.data.outgoing.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Waiting for approval").font(.headline)
                    ForEach(people.data.outgoing) { request in
                        PendingRequestRow(targetId: request.targetId)
                    }
                }
            }

            if !people.data.incoming.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("People who want to follow you").font(.headline)
                    ForEach(people.data.incoming) { request in
                        RequestRow(request: request, people: people)
                    }
                }
            }

            VStack(spacing: Spacing.s) {
                NavigationLink(value: PeopleTabRoute()) {
                    Label("Find people you know", systemImage: "person.2")
                }
                .buttonStyle(.secondary)
                NavigationLink(value: CreatePostRoute()) {
                    Label("Make your first post", systemImage: "plus.circle")
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(Spacing.l)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Spacing.m)
        .accessibilityIdentifier("feed.empty")
        .followBackPrompt(people: people)
    }
}

/// A person you have requested, resolved to a name through the match list
/// (they are not yet visible by id until they approve).
struct PendingRequestRow: View {
    let targetId: UUID
    private var match: MatchedPerson? { ContactSync.shared.matches.first { $0.id == targetId } }

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let match {
                AvatarView(profile: match.profile, size: 40)
                Text(match.savedName).font(.body)
            } else {
                Circle().fill(Color.subtleBackground).frame(width: 40, height: 40)
                Text("Someone you requested").font(.body)
            }
            Spacer()
            Text("Requested").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

nonisolated struct ActivityRoute: Hashable, Sendable {}
nonisolated struct PeopleTabRoute: Hashable, Sendable {}
nonisolated struct CreatePostRoute: Hashable, Sendable {}
nonisolated struct ComposeResponseRoute: Hashable, Sendable { let postId: UUID }

/// Feed-related destinations that need the shared feed model.
struct FeedDestinations: ViewModifier {
    let feed: FeedModel
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ActivityRoute.self) { _ in ActivityView() }
            .navigationDestination(for: PeopleTabRoute.self) { _ in PeopleTab() }
            .navigationDestination(for: CreatePostRoute.self) { _ in CreatePostView(onPublished: { Task { await feed.refresh() } }) }
            .navigationDestination(for: ComposeResponseRoute.self) { route in
                ComposeResponseView(postId: route.postId, onSent: {})
            }
    }
}

extension View {
    func feedDestinations(feed: FeedModel) -> some View { modifier(FeedDestinations(feed: feed)) }
}

