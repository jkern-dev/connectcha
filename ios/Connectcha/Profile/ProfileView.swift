import SwiftUI

/// Another person's profile. Minimal (spec 8.3) until you follow them; full
/// (spec 8.1) once approved. Never shows a phone number, and never shows this
/// person's follower or following counts (spec 8.4).
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: ProfileModel
    @State private var confirmUnfollow = false
    @State private var confirmRemove = false
    @State private var confirmCancel = false

    init(route: ProfileRoute) {
        _model = State(initialValue: ProfileModel(userId: route.userId, phoneHash: route.phoneHash))
    }

    var body: some View {
        ScrollView {
            if let page = model.page {
                VStack(spacing: Spacing.l) {
                    header(page)
                    actions(page)
                    if page.canView {
                        PostsGrid(items: page.posts, authorName: page.profile.displayName)
                    } else {
                        Text(model.canRequest
                             ? "Request to follow to see their posts and stories."
                             : "Posts and stories are shared with people they approve.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.l)
                            .accessibilityIdentifier("profile.minimalHint")
                    }
                }
                .padding(.vertical, Spacing.l)
            } else if let error = model.error {
                VStack(spacing: Spacing.m) {
                    ErrorText(text: error)
                    Button("Try again") { Task { await model.load() } }.buttonStyle(.secondary)
                }
                .padding(Spacing.l)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(model.page?.profile.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let page = model.page, !page.isMe, page.relationship.iFollow || page.relationship.followsMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if page.relationship.iFollow {
                            Button("Unfollow", systemImage: "person.badge.minus", role: .destructive) { confirmUnfollow = true }
                        }
                        if page.relationship.followsMe {
                            Button("Remove follower", systemImage: "person.fill.xmark", role: .destructive) { confirmRemove = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Unfollow \(model.page?.profile.displayName ?? "")?", isPresented: $confirmUnfollow, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) { Task { await model.unfollow(); await appModel.refreshMe() } }
        } message: {
            Text("You'll stop seeing their posts and stories. They won't be told.")
        }
        .confirmationDialog("Remove \(model.page?.profile.displayName ?? "") as a follower?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.removeFollower(); await appModel.refreshMe() } }
        } message: {
            Text("They'll immediately stop seeing your posts and stories. They won't be told.")
        }
        .confirmationDialog("Cancel your request?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel request", role: .destructive) { Task { await model.cancelRequest() } }
            Button("Keep it", role: .cancel) {}
        }
        .confirmationDialog(
            model.followBackOffer.map { "Follow \($0.displayName) back?" } ?? "",
            isPresented: Binding(get: { model.followBackOffer != nil }, set: { if !$0 { model.followBackOffer = nil } }),
            titleVisibility: .visible
        ) {
            Button("Request to follow") { Task { await model.request() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("They'll need to approve before you see their posts.")
        }
    }

    private func header(_ page: ProfilePage) -> some View {
        VStack(spacing: Spacing.s) {
            AvatarView(profile: page.profile, size: 120, storyRing: page.hasActiveStory)
                .padding(.top, Spacing.s)
            Text(page.profile.displayName)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.s) {
                Text(DisplayNames.shared.contactsLabel(for: page.profile.id))
                if page.relationship.followsMe {
                    Text("·").accessibilityHidden(true)
                    Text("Follows you")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if page.canView, let bio = page.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.m)
    }

    @ViewBuilder
    private func actions(_ page: ProfilePage) -> some View {
        let r = page.relationship
        VStack(spacing: Spacing.s) {
            if r.incomingRequestId != nil {
                VStack(spacing: Spacing.s) {
                    Text("\(page.profile.displayName) wants to follow you.")
                        .font(.body.weight(.medium))
                    HStack(spacing: Spacing.s) {
                        Button("Approve") { Task { await model.approveIncoming(); await appModel.refreshUnread() } }.buttonStyle(.pill)
                        Button("Decline") { Task { await model.declineIncoming(); await appModel.refreshUnread() } }.buttonStyle(.quietPill)
                    }
                }
            }
            if r.iFollow {
                HStack(spacing: Spacing.s) {
                    Button {
                        Task { await model.setBell(!r.bellOn) }
                    } label: {
                        Label(r.bellOn ? "Notifications on" : "Notify me", systemImage: r.bellOn ? "bell.fill" : "bell")
                    }
                    .buttonStyle(r.bellOn ? .pill : .quietPill)
                    .accessibilityHint("Get a notification when they post or add a story")
                    Button("Following", systemImage: "checkmark") { confirmUnfollow = true }
                        .buttonStyle(.quietPill)
                        .accessibilityHint("Tap to unfollow")
                }
            } else if r.outgoingRequestId != nil {
                Button("Requested") { confirmCancel = true }
                    .buttonStyle(.quietPill)
                    .accessibilityHint("Waiting for approval. Tap to cancel.")
            } else if model.canRequest {
                Button("Request to follow") { Task { await model.request() } }
                    .buttonStyle(.pill)
            }
            if r.hasConversation {
                NavigationLink(value: ConversationRoute(conversationId: nil, otherUserId: page.profile.id)) {
                    Label("Message", systemImage: "bubble.left")
                }
                .buttonStyle(.quietPill)
            }
            ErrorText(text: model.error)
        }
        .disabled(model.busy)
        .padding(.horizontal, Spacing.m)
    }
}

/// Navigation target for a conversation (filled in by M7).
nonisolated struct ConversationRoute: Hashable, Sendable {
    let conversationId: UUID?
    let otherUserId: UUID?
}

/// Navigation target for a post (filled in by M5).
nonisolated struct PostRoute: Hashable, Sendable {
    let postId: UUID
}

/// Three-column grid of post covers (spec 8.1).
struct PostsGrid: View {
    let items: [ProfileGridItem]
    var authorName: String

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        if items.isEmpty {
            Text("No posts yet.")
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.m)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    NavigationLink(value: PostRoute(postId: item.id)) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let cover = item.cover {
                                    RemoteImage(mediaId: cover.id, variant: .thumb)
                                } else {
                                    Color.subtleBackground
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if item.mediaCount > 1 {
                                    Image(systemName: "square.on.square.fill").padding(6).foregroundStyle(.white).shadow(radius: 2)
                                } else if item.cover?.kind == .video {
                                    Image(systemName: "play.fill").padding(6).foregroundStyle(.white).shadow(radius: 2)
                                }
                            }
                            .clipped()
                            .contentShape(Rectangle())
                            .accessibilityLabel("Post by \(authorName)\(item.cover?.kind == .video ? ", video" : "")")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
