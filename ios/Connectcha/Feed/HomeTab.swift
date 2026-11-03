import SwiftUI

/// Home: today's snapshots, then the day's photos laid out on the table,
/// grouped under day headings. Share and Letters sit in the top bar.
struct HomeTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    var start: HomeStart = .none

    @State private var feed = FeedModel()
    @State private var people = PeopleModel()
    @State private var tray = StoryTrayModel()
    @State private var likersFor: Post?
    @State private var path = NavigationPath()
    @State private var sharing = false
    @State private var startHandled = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    header
                    if !tray.groups.isEmpty || appModel.me != nil {
                        SnapshotsSection(model: tray)
                    }
                    if !feed.loadedOnce {
                        ProgressView("Setting the table…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if feed.posts.isEmpty {
                        EmptyFeedView(people: people)
                    } else {
                        feedList
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .kitchenTableRoot(title: "Home")
            .refreshable {
                await feed.refresh()
                await tray.load()
                await people.load()
                await appModel.refreshUnread()
            }
            .task {
                await feed.refresh()
                await tray.load()
                await people.load()
                if !startHandled {
                    startHandled = true
                    switch start {
                    case .letters: path.append(LettersRoute())
                    case .share: sharing = true
                    case .none: break
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await feed.refresh(); await tray.load() } }
                if phase == .background { Task { await feed.markSeen() } }
            }
            .onDisappear { Task { await feed.markSeen() } }
            .sheet(item: $likersFor) { post in
                LikersView(post: post)
            }
            .sheet(isPresented: $sharing) {
                ShareComposerSheet(onPublished: { Task { await feed.refresh(); await tray.load() } })
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

    // MARK: Header

    private var header: some View {
        AdaptiveStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateWords.long())
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Palette.muted)
                BrandMark(size: .title)
            }
            .accessibilityElement(children: .combine)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            // Side by side normally; two full-width rows at accessibility sizes.
            AdaptiveStack(alignment: .leading, spacing: 10) {
                NavigationLink(value: LettersRoute()) {
                    lettersLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appModel.unread.unreadConversations > 0
                                    ? "Letters, \(appModel.unread.unreadConversations) unread"
                                    : "Letters")
                Button { sharing = true } label: {
                    Label("Share", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.pill)
                .accessibilityHint("Photos for the table, or a snapshot that is gone tomorrow")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.s)
    }

    @ViewBuilder
    private var lettersLabel: some View {
        if typeSize.isAccessibilitySize {
            HStack {
                Text("Letters").font(.body.weight(.semibold))
                Spacer(minLength: 0)
                if appModel.unread.unreadConversations > 0 { UnreadBadge(count: appModel.unread.unreadConversations) }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .background(Color.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1.5))
            .foregroundStyle(Palette.ink)
        } else {
            Image(systemName: "envelope")
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Color.cardBackground, in: Circle())
                .shadow(color: Palette.shadow.opacity(0.08), radius: 1, y: 1)
                .overlay(alignment: .topTrailing) {
                    if appModel.unread.unreadConversations > 0 {
                        UnreadBadge(count: appModel.unread.unreadConversations).offset(x: 4, y: -4)
                    }
                }
        }
    }

    // MARK: Feed

    private var feedList: some View {
        let marker = FeedModel.caughtUpIndex(posts: feed.posts, seenThrough: feed.seenThrough)
        let groups = FeedModel.dayGroups(posts: feed.posts)
        return ForEach(groups) { group in
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeading(title: group.label, rule: true)
                    .padding(.horizontal, Spacing.gutter)
                ForEach(Array(group.posts.enumerated()), id: \.element.id) { offset, post in
                    let index = group.startIndex + offset
                    if marker == index { CaughtUpMarker() }
                    PostCard(
                        post: post,
                        onLike: { Task { await feed.toggleLike(post) } },
                        onOpenLikers: { likersFor = post },
                        onOpenPost: { path.append(PostRoute(postId: post.id)) },
                        onMessage: { path.append(ComposeResponseRoute(postId: post.id)) },
                        onMenu: post.isMine ? { path.append(PostRoute(postId: post.id)) } : nil
                    )
                    .padding(.horizontal, Spacing.gutter)
                    .onAppear { Task { await feed.loadMoreIfNeeded(current: post) } }
                    if marker == feed.posts.count, index == feed.posts.count - 1 { CaughtUpMarker() }
                }
            }
        }
    }
}

struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.accentColor, in: Capsule())
            .accessibilityHidden(true)
    }
}

struct CaughtUpMarker: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're caught up").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("Everything new since you were last here is above. Older photos continue below.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softBox()
        .padding(.horizontal, Spacing.gutter)
        .accessibilityElement(children: .combine)
    }
}

/// Spec 9.2: pending requests, prompts to invite or share, and why the table
/// is empty. Never filler content.
struct EmptyFeedView: View {
    @Environment(AppModel.self) private var appModel
    let people: PeopleModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Nothing on the table yet")
                    .font(.serif(.title2, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Connectcha only shows photos from people who have let you in. It fills up as they say yes.")
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !people.data.outgoing.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Waiting for their yes").font(.body.weight(.semibold))
                    ForEach(people.data.outgoing) { request in
                        PendingRequestRow(targetId: request.targetId)
                    }
                }
            }

            if !people.data.incoming.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Waiting for your yes").font(.body.weight(.semibold))
                    ForEach(people.data.incoming) { request in
                        RequestRow(request: request, people: people)
                    }
                }
            }

            VStack(spacing: Spacing.s) {
                NavigationLink(value: PeopleTabRoute()) {
                    Text("Find people you know")
                }
                .buttonStyle(.secondary)
                NavigationLink(value: CreatePostRoute()) {
                    Text("Share your first photo")
                }
                .buttonStyle(.secondary)
            }
        }
        .card(padding: Spacing.l)
        .padding(.horizontal, Spacing.gutter)
        .accessibilityIdentifier("feed.empty")
        .followBackPrompt(people: people)
    }
}

/// A person you have asked to follow, resolved to a name through the match
/// list (they are not yet visible by id until they approve).
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
                Text("Someone you asked").font(.body)
            }
            Spacer()
            Text("Asked").font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
}

nonisolated struct PeopleTabRoute: Hashable, Sendable {}
nonisolated struct CreatePostRoute: Hashable, Sendable {}
nonisolated struct ComposeResponseRoute: Hashable, Sendable { let postId: UUID }

/// Feed-related destinations that need the shared feed model.
struct FeedDestinations: ViewModifier {
    let feed: FeedModel
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: PeopleTabRoute.self) { _ in PeopleTab(embedded: true) }
            .navigationDestination(for: CreatePostRoute.self) { _ in CreatePostView(onPublished: { Task { await feed.refresh() } }) }
            .navigationDestination(for: ComposeResponseRoute.self) { route in
                ComposeResponseView(postId: route.postId, onSent: {})
            }
    }
}

extension View {
    func feedDestinations(feed: FeedModel) -> some View { modifier(FeedDestinations(feed: feed)) }
}
