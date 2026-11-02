import SwiftUI

/// Spec 8.5 Inbox: conversations, unread first by recency, badge for unread.
struct InboxTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var inbox = InboxModel()

    var body: some View {
        NavigationStack {
            List {
                if inbox.loadedOnce, inbox.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("No messages yet").font(.headline)
                        Text("Conversations start when someone responds to a post or story. Replies to your posts land here.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.s)
                }
                ForEach(inbox.items) { item in
                    NavigationLink(value: ConversationRoute(conversationId: item.conversationId, otherUserId: item.other.id)) {
                        InboxRow(item: item)
                    }
                }
                if let error = inbox.error { ErrorText(text: error) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Inbox")
            .refreshable { await inbox.load(); await appModel.refreshUnread() }
            .task { await inbox.load() }
            .onChange(of: scenePhase) { _, p in if p == .active { Task { await inbox.load() } } }
            .appDestinations()
            .navigationDestination(for: ConversationRoute.self) { route in
                ConversationView(route: route, onChange: { Task { await inbox.load(); await appModel.refreshUnread() } })
            }
        }
    }
}

struct InboxRow: View {
    let item: InboxItem

    private var preview: String {
        guard let m = item.lastMessage else { return "" }
        switch m.kind {
        case .text: return m.body
        case .postResponse: return "Responded to a post: \(m.body)"
        case .storyResponse: return "Replied to a story: \(m.body)"
        case .storyReaction: return "Reacted \(m.body) to a story"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            AvatarView(profile: item.other, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.other.displayName).font(item.unread ? .headline : .body.weight(.medium))
                    Spacer()
                    Text(RelativeTime.string(from: item.lastMessageAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(item.unread ? .primary : .secondary)
                    .lineLimit(2)
                if !item.canSend {
                    Text("Read only").font(.caption).foregroundStyle(.secondary)
                }
            }
            if item.unread {
                Circle().fill(Color.accentColor).frame(width: 10, height: 10).accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
