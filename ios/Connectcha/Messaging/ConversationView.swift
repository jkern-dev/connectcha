import SwiftUI

/// One-to-one letters (spec 7) with photo and snapshot previews, realtime
/// updates, and the read-only state when neither follows the other (S13).
struct ConversationView: View {
    @Environment(AppModel.self) private var appModel
    let route: ConversationRoute
    /// Shown as the right-hand page of Letters (wide windows): it draws its
    /// own header instead of taking over the navigation bar.
    var embedded = false
    var onChange: () -> Void

    @State private var model: ConversationModel?
    @State private var resolving = true
    @State private var resolveError: String?
    @FocusState private var composing: Bool

    var body: some View {
        if embedded {
            VStack(spacing: 0) {
                embeddedHeader
                core.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            pushed
        }
    }

    @ViewBuilder
    private var embeddedHeader: some View {
        if let other = model?.page?.other {
            NavigationLink(value: ProfileRoute(userId: other.id, phoneHash: nil)) {
                HStack(spacing: Spacing.s) {
                    AvatarView(profile: other, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(other.displayName).font(.serif(.title3, weight: .bold)).foregroundStyle(Palette.ink)
                        Text("Only the two of you can read this").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(other.displayName). Only the two of you can read this. Opens their page.")
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        }
    }

    private var core: some View {
        Group {
            if let model {
                content(model)
            } else if let resolveError {
                VStack(spacing: Spacing.m) { ErrorText(text: resolveError) }.padding()
            } else {
                ProgressView()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task { await resolve() }
        .onDisappear { model?.stopListening(); onChange() }
    }

    private var pushed: some View {
        core
        .navigationTitle(model?.page?.other.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let other = model?.page?.other {
                ToolbarItem(placement: .principal) {
                    NavigationLink(value: ProfileRoute(userId: other.id, phoneHash: nil)) {
                        VStack(spacing: 0) {
                            Text(other.displayName).font(.serif(.headline, weight: .bold)).foregroundStyle(Palette.ink)
                            Text("Only the two of you can read this").font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(other.displayName). Only the two of you can read this. Opens their page.")
                }
            }
        }
    }

    private func resolve() async {
        if let id = route.conversationId {
            model = ConversationModel(conversationId: id)
        } else if let other = route.otherUserId {
            // Opened from a profile: find the pair's conversation in the inbox.
            if let items: [InboxItem] = try? await API.shared.rpc("get_inbox"),
               let match = items.first(where: { $0.other.id == other }) {
                model = ConversationModel(conversationId: match.conversationId)
            } else {
                resolveError = "A letter starts when you write back to one of their photos or snapshots."
                return
            }
        }
        await model?.load()
        model?.startListening()
    }

    @ViewBuilder
    private func content(_ model: ConversationModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if index == 0 || !Calendar.current.isDate(message.createdAt, inSameDayAs: model.messages[index - 1].createdAt) {
                                DayDivider(label: FeedModel.dayLabel(for: message.createdAt))
                            }
                            MessageBubble(message: message, isMine: message.senderId == appModel.userId, other: model.page?.other, currentUserId: appModel.userId)
                                .id(message.id)
                        }
                    }
                    .padding(Spacing.m)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear {
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            composer(model)
        }
    }

    @ViewBuilder
    private func composer(_ model: ConversationModel) -> some View {
        @Bindable var model = model
        VStack(spacing: Spacing.xs) {
            if let page = model.page, !page.canSend {
                VStack(spacing: 4) {
                    Label("You can read this conversation but not send new messages", systemImage: "lock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Letters work while at least one of you follows the other.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(Spacing.m)
                .background(Color.subtleBackground)
                .accessibilityIdentifier("conversation.readOnly")
            } else {
                ErrorText(text: model.error).padding(.horizontal, Spacing.m)
                HStack(alignment: .bottom, spacing: Spacing.s) {
                    TextField("Write to \(model.page?.other.displayName ?? "")…", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composing)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1.5))
                        .onChange(of: model.draft) { _, new in if new.count > 2000 { model.draft = String(new.prefix(2000)) } }
                        .accessibilityIdentifier("conversation.composer")
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(model.draft.trimmingCharacters(in: .whitespaces).isEmpty ? Palette.border : Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.sending)
                    .accessibilityLabel("Send")
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Color.cardBackground)
            }
        }
    }
}

struct DayDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            Text(label).font(.serif(.subheadline)).foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let other: Profile?
    var currentUserId: UUID? = nil

    /// "your photo" when the post or story is the reader's own.
    private func owner(_ author: Profile) -> String {
        author.id == currentUserId ? "your" : "\(author.displayName)'s"
    }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            if message.kind != .text {
                preview
            }
            Text(message.body)
                .font(message.kind == .storyReaction ? .largeTitle : .body)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    isMine ? Palette.tint : Color.cardBackground,
                    in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: isMine ? 18 : 4,
                                               bottomTrailingRadius: isMine ? 4 : 18, topTrailingRadius: 18, style: .continuous)
                )
                .shadow(color: Palette.shadow.opacity(isMine ? 0 : 0.08), radius: 1, y: 1)
            Text("\(isMine ? "You" : (other?.displayName ?? "")) · \(RelativeTime.string(from: message.createdAt))")
                .font(.caption).foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        switch message.kind {
        case .postResponse:
            if let post = message.post {
                NavigationLink(value: PostRoute(postId: post.id)) {
                    PreviewCard(title: "About \(owner(post.author)) photo", mediaId: post.cover?.id)
                }
                .buttonStyle(.plain)
            } else {
                PreviewCard(title: "That photo is no longer on the table", mediaId: nil)
            }
        case .storyResponse, .storyReaction:
            if let story = message.story {
                PreviewCard(title: "About \(owner(story.author)) snapshot", mediaId: story.media.id)
            } else {
                PreviewCard(title: "That snapshot has gone", mediaId: nil)
            }
        case .text:
            EmptyView()
        }
    }
}

struct PreviewCard: View {
    let title: String
    let mediaId: UUID?

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let mediaId {
                RemoteImage(mediaId: mediaId, variant: .thumb)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.subtleBackground)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "nosign").foregroundStyle(Palette.muted))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .padding(.trailing, 6)
        .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityLabel(title)
    }
}

/// Spec 5.4: "Write back to X" under a photo opens this; the first message is
/// the response that creates the conversation.
struct ComposeResponseView: View {
    @Environment(\.dismiss) private var dismiss
    let postId: UUID
    var onSent: () -> Void

    @State private var post: Post?
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    nonisolated struct RespondParams: Encodable, Sendable {
        let pPostId: UUID; let pBody: String
        enum CodingKeys: String, CodingKey { case pPostId = "p_post_id", pBody = "p_body" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let post {
                    PreviewCard(title: "On the back of \(post.author.displayName)'s photo", mediaId: post.media.first?.id)
                    TextField("Write to \(post.author.displayName)…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .padding(Spacing.m)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1.5))
                        .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
                    ErrorText(text: error)
                    Button {
                        Task { await send() }
                    } label: {
                        if sending { ProgressView().tint(.white) } else { Text("Send") }
                    }
                    .buttonStyle(.primary)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                    Text("This isn't a public comment. Only \(post.author.displayName) will read it, as a letter.")
                        .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView()
                }
            }
            .padding(Spacing.gutter)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(post.map { "Write back to \($0.author.displayName)" } ?? "Write back")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            post = try? await API.shared.rpc("get_post", FeedModel.PostParams(pPostId: postId))
            focused = true
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let _: SentMessage = try await API.shared.rpc("respond_to_post", RespondParams(pPostId: postId, pBody: text))
            onSent()
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}
