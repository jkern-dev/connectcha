import SwiftUI

/// One-to-one conversation (spec 7) with post and story previews, realtime
/// updates, and the read-only state when neither follows the other (S13).
struct ConversationView: View {
    @Environment(AppModel.self) private var appModel
    let route: ConversationRoute
    var onChange: () -> Void

    @State private var model: ConversationModel?
    @State private var resolving = true
    @State private var resolveError: String?
    @FocusState private var composing: Bool

    var body: some View {
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
        .navigationTitle(model?.page?.other.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolve() }
        .onDisappear { model?.stopListening(); onChange() }
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
                resolveError = "You can start a conversation by responding to one of their posts or stories."
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
                    LazyVStack(spacing: Spacing.s) {
                        ForEach(model.messages) { message in
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
                        .font(.subheadline.weight(.medium))
                    Text("Messages work while at least one of you follows the other.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(Spacing.m)
                .background(Color.subtleBackground)
                .accessibilityIdentifier("conversation.readOnly")
            } else {
                ErrorText(text: model.error).padding(.horizontal, Spacing.m)
                HStack(alignment: .bottom, spacing: Spacing.s) {
                    TextField("Message \(model.page?.other.displayName ?? "")", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composing)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onChange(of: model.draft) { _, new in if new.count > 2000 { model.draft = String(new.prefix(2000)) } }
                        .accessibilityIdentifier("conversation.composer")
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.sending)
                    .accessibilityLabel("Send")
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Color.appBackground)
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let other: Profile?
    var currentUserId: UUID? = nil

    /// "your post" when the post or story is the reader's own.
    private func owner(_ author: Profile) -> String {
        author.id == currentUserId ? "your" : "\(author.displayName)'s"
    }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if message.kind != .text {
                preview
            }
            Text(message.body)
                .font(message.kind == .storyReaction ? .largeTitle : .body)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(isMine ? Color.accentColor : Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(isMine ? Color.white : Color.primary)
            Text(RelativeTime.string(from: message.createdAt))
                .font(.caption2).foregroundStyle(.secondary)
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
                    PreviewCard(title: "Responding to \(owner(post.author)) post", mediaId: post.cover?.id)
                }
                .buttonStyle(.plain)
            } else {
                PreviewCard(title: "Post no longer available", mediaId: nil)
            }
        case .storyResponse, .storyReaction:
            if let story = message.story {
                PreviewCard(title: "\(message.kind == .storyReaction ? "Reacted to" : "Replying to") \(owner(story.author)) story", mediaId: story.media.id)
            } else {
                PreviewCard(title: "Story no longer available", mediaId: nil)
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
                    .frame(width: 44, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.subtleBackground)
                    .frame(width: 44, height: 56)
                    .overlay(Image(systemName: "nosign").foregroundStyle(.secondary))
            }
            Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(8)
        .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(title)
    }
}

/// Spec 5.4: the "Message [name]" box under a post opens this; the first
/// message is the response that creates the conversation.
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
        VStack(spacing: Spacing.m) {
            if let post {
                PreviewCard(title: "Responding to \(post.author.displayName)'s post. Only they will see this.", mediaId: post.media.first?.id)
                    .padding(.horizontal, Spacing.m)
                TextField("Message \(post.author.displayName)", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                    .padding(Spacing.m)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, Spacing.m)
                    .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
                ErrorText(text: error).padding(.horizontal, Spacing.m)
                Button {
                    Task { await send() }
                } label: {
                    if sending { ProgressView().tint(.white) } else { Text("Send") }
                }
                .buttonStyle(.primary)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                .padding(.horizontal, Spacing.m)
                Text("This isn't a public comment. It goes to \(post.author.displayName) as a private message.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, Spacing.l)
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding(.top, Spacing.m)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(post.map { "Message \($0.author.displayName)" } ?? "Message")
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
