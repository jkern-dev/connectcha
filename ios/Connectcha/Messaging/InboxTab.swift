import SwiftUI

/// "Letters": conversations, unread first by recency (spec 8.5 Inbox). Pushed
/// from Home's top bar rather than a tab of its own.
struct LettersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var inbox = InboxModel()
    /// The thread open on the right page when the window is wide.
    @State private var selected: ConversationRoute?
    private let wide = WideLayout()

    var body: some View {
        Group {
            if wide.isOn {
                // Unfolded: the threads on the left page, the open letter on
                // the right, so reading one never means leaving the list.
                TwoPages {
                    list
                } right: {
                    if let selected {
                        ConversationView(route: selected, embedded: true, onChange: {
                            Task { await inbox.load(); await appModel.refreshUnread() }
                        })
                        .id(selected)
                    } else {
                        Text(inbox.loadedOnce && inbox.items.isEmpty ? "" : "Choose a letter to read it here.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                list
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Letters")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await inbox.load(); await appModel.refreshUnread() }
        .task { await inbox.load(); selectFirstIfNeeded() }
        .onAppear { Task { await inbox.load(); await appModel.refreshUnread(); selectFirstIfNeeded() } }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await inbox.load() } } }
        .onChange(of: wide.isOn) { _, _ in selectFirstIfNeeded() }
    }

    /// With two pages there is always a letter open: the newest one.
    private func selectFirstIfNeeded() {
        guard wide.isOn, selected == nil, let first = inbox.items.first else { return }
        selected = ConversationRoute(conversationId: first.conversationId, otherUserId: first.other.id)
    }

    @ViewBuilder
    private func row(_ item: InboxItem) -> some View {
        let route = ConversationRoute(conversationId: item.conversationId, otherUserId: item.other.id)
        if wide.isOn {
            let isOpen = selected?.conversationId == item.conversationId
            Button { selected = route } label: {
                InboxRow(item: item)
                    .overlay {
                        if isOpen {
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.cardPress)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        } else {
            NavigationLink(value: route) {
                InboxRow(item: item)
            }
            .buttonStyle(.cardPress)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ScreenHeader(title: "Letters", subtitle: "Between you and one other person. Nobody else can read them.")
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, Spacing.xs)
                if inbox.loadedOnce, inbox.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("No letters yet").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("A letter starts when someone writes back to a photo or a snapshot. Write-backs to yours land here.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                    .padding(.horizontal, Spacing.gutter)
                }
                ForEach(inbox.items) { item in
                    row(item)
                        .padding(.horizontal, Spacing.gutter)
                }
                if let error = inbox.error { ErrorText(text: error).padding(.horizontal, Spacing.gutter) }
                if inbox.loadedOnce, !inbox.items.isEmpty {
                    Text("You can write to anyone in your circle once a letter has started. People outside it can't write to you.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                        .padding(.horizontal, Spacing.gutter + 4)
                        .padding(.top, Spacing.xs)
                }
            }
            .padding(.vertical, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
    }
}

struct InboxRow: View {
    let item: InboxItem
    @Environment(\.dynamicTypeSize) private var typeSize

    private var about: String? {
        guard let m = item.lastMessage else { return nil }
        switch m.kind {
        case .text: return nil
        case .postResponse: return "About a photo"
        case .storyResponse, .storyReaction: return "About a snapshot"
        }
    }

    private var preview: String {
        guard let m = item.lastMessage else { return "" }
        return m.body
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            AvatarView(profile: item.other, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                AdaptiveStack(spacing: Spacing.s) {
                    Text(item.other.displayName)
                        .font(.body.weight(item.unread ? .bold : .semibold))
                        .foregroundStyle(Palette.ink)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text(item.unread ? "\(RelativeTime.string(from: item.lastMessageAt)) · new" : RelativeTime.string(from: item.lastMessageAt))
                        .font(.footnote.weight(item.unread ? .bold : .regular))
                        .foregroundStyle(item.unread ? Color.accentColor : Palette.muted)
                }
                if let about {
                    Text(about).font(.footnote).foregroundStyle(Palette.muted)
                }
                Text(preview)
                    .captionSerif()
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                if !item.canSend {
                    Text("Read only").font(.footnote).foregroundStyle(Palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .padding(.leading, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .leading) {
            if item.unread {
                UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card)
                    .fill(Color.accentColor)
                    .frame(width: 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Palette.shadow.opacity(0.10), radius: 2, y: 1)
    }
}
