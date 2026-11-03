import SwiftUI

/// Someone's page. Minimal (spec 8.3) until you follow them; full (spec 8.1)
/// once approved. Never shows a phone number, and never shows this person's
/// follower or following counts (spec 8.4). Their photos are a filmstrip, not
/// a grid.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
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
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header(page)
                    actions(page)
                    if page.canView {
                        filmstrip(page)
                        privacyNote(page)
                    } else {
                        lockedNote(page)
                    }
                }
                .padding(.vertical, Spacing.s)
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
                            Button("Stop following", systemImage: "person.badge.minus", role: .destructive) { confirmUnfollow = true }
                        }
                        if page.relationship.followsMe {
                            Button("Take them out of your circle", systemImage: "person.fill.xmark", role: .destructive) { confirmRemove = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Stop following \(model.page?.profile.displayName ?? "")?", isPresented: $confirmUnfollow, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) { Task { await model.unfollow(); await appModel.refreshMe() } }
        } message: {
            Text("You'll stop seeing their photos and snapshots. They won't be told.")
        }
        .confirmationDialog("Take \(model.page?.profile.displayName ?? "") out of your circle?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.removeFollower(); await appModel.refreshMe() } }
        } message: {
            Text("They'll immediately stop seeing your photos and snapshots. They won't be told.")
        }
        .confirmationDialog("Take back your request?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Take it back", role: .destructive) { Task { await model.cancelRequest() } }
            Button("Keep waiting", role: .cancel) {}
        }
        .confirmationDialog(
            model.followBackOffer.map { "Follow \($0.displayName) back?" } ?? "",
            isPresented: Binding(get: { model.followBackOffer != nil }, set: { if !$0 { model.followBackOffer = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ask to follow") { Task { await model.request() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("They'll need to say yes before you see their photos.")
        }
    }

    // MARK: Header

    private func header(_ page: ProfilePage) -> some View {
        AdaptiveStack(alignment: .leading, spacing: Spacing.m) {
            AvatarView(profile: page.profile, size: 88, storyRing: page.hasActiveStory)
            VStack(alignment: .leading, spacing: 6) {
                Text(page.profile.displayName)
                    .font(.serif(.largeTitle, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusLine(page))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if page.canView, let bio = page.bio, !bio.isEmpty {
                    Text(bio)
                        .captionSerif()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }

    private func statusLine(_ page: ProfilePage) -> String {
        var parts = [DisplayNames.shared.contactsLabel(for: page.profile.id)]
        if page.relationship.followsMe { parts.append("follows you") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ page: ProfilePage) -> some View {
        let r = page.relationship
        let name = page.profile.displayName
        VStack(alignment: .leading, spacing: 10) {
            if r.incomingRequestId != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(name) is asking to see your photos. Saying yes lets \(name) see your photos and snapshots.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                    AdaptiveStack(alignment: .leading, spacing: Spacing.s) {
                        Button("Yes, let \(name) in") { Task { await model.approveIncoming(); await appModel.refreshUnread() } }
                            .buttonStyle(.pill)
                            .accessibilityIdentifier("request.approve")
                        Button("Not now") { Task { await model.declineIncoming(); await appModel.refreshUnread() } }
                            .buttonStyle(.quietPill)
                            .accessibilityIdentifier("request.decline")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            }
            AdaptiveStack(alignment: .leading, spacing: Spacing.s) {
                if r.hasConversation {
                    NavigationLink(value: ConversationRoute(conversationId: nil, otherUserId: page.profile.id)) {
                        Label("Your letters", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill)
                }
                if r.iFollow {
                    Button("Following", systemImage: "checkmark") { confirmUnfollow = true }
                        .buttonStyle(.quietPill)
                        .accessibilityHint("Tap to stop following")
                } else if r.outgoingRequestId != nil {
                    Button("Asked") { confirmCancel = true }
                        .buttonStyle(.quietPill)
                        .accessibilityHint("Waiting for their yes. Tap to take it back.")
                } else if model.canRequest {
                    Button("Ask to follow") { Task { await model.request() } }
                        .buttonStyle(.pill)
                }
            }
            if r.iFollow {
                Toggle(isOn: Binding(get: { r.bellOn }, set: { on in Task { await model.setBell(on) } })) {
                    Text("Tell me when \(name) shares something")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Color.accentColor)
                .accessibilityHint("A notification when they share a photo or a snapshot")
                .card(padding: 14)
            }
            ErrorText(text: model.error)
        }
        .disabled(model.busy)
        .padding(.horizontal, Spacing.gutter)
    }

    // MARK: Photos

    @ViewBuilder
    private func filmstrip(_ page: ProfilePage) -> some View {
        let name = page.profile.displayName
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "\(name)'s photos", note: page.posts.isEmpty ? nil : "newest first")
                .padding(.horizontal, Spacing.gutter)
            if page.posts.isEmpty {
                Text("Nothing on the table yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, Spacing.gutter)
            } else if typeSize.isAccessibilitySize {
                VStack(spacing: Spacing.m) {
                    ForEach(page.posts) { item in FilmstripItem(item: item, authorName: name, width: nil) }
                }
                .padding(.horizontal, Spacing.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(page.posts) { item in FilmstripItem(item: item, authorName: name, width: 200) }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func privacyNote(_ page: ProfilePage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Only you see this page the way you see it").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            Text("Who else follows \(page.profile.displayName), and how many, is never shown. To anyone.")
                .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softBox()
        .padding(.horizontal, Spacing.gutter)
    }

    private func lockedNote(_ page: ProfilePage) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "lock").font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            Text("\(page.profile.displayName)'s photos open when they say yes")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(model.canRequest
                 ? "Ask to follow, and you'll see their photos and snapshots once they let you in. Nothing else about them is shown here, to anyone."
                 : "You'll see their photos and snapshots once they let you in. Nothing else about them is shown here, to anyone.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
        .padding(.horizontal, Spacing.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.minimalHint")
    }
}

/// Navigation target for a conversation.
nonisolated struct ConversationRoute: Hashable, Sendable {
    let conversationId: UUID?
    let otherUserId: UUID?
}

/// Navigation target for a post.
nonisolated struct PostRoute: Hashable, Sendable {
    let postId: UUID
}

/// One photo in a filmstrip: the cover, then the date underneath.
struct FilmstripItem: View {
    let item: ProfileGridItem
    var authorName: String
    /// Fixed width for the horizontal strip; nil fills the line (large text).
    var width: CGFloat?

    var body: some View {
        NavigationLink(value: PostRoute(postId: item.id)) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let cover = item.cover {
                        RemoteImage(mediaId: cover.id, variant: .thumb)
                    } else {
                        Color.subtleBackground
                    }
                }
                .frame(width: width, height: width.map { $0 * 1.2 } ?? 240)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if item.mediaCount > 1 || item.cover?.kind == .video {
                        Text(item.mediaCount > 1 ? "\(item.mediaCount) photos" : "video")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.printInk)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Palette.printPaper.opacity(0.92), in: Capsule())
                            .padding(8)
                    }
                }
                Text(FeedModel.dayLabel(for: item.publishedAt))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Post by \(authorName), \(FeedModel.dayLabel(for: item.publishedAt))\(item.cover?.kind == .video ? ", video" : "")")
    }
}
