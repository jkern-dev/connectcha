import SwiftUI

/// Spec 6 story tray: your own story first (A3), then people with unseen
/// stories, most recent first. Ordering comes from the server
/// (get_story_tray) and never depends on who you interact with.
@MainActor
@Observable
final class StoryTrayModel {
    private(set) var groups: [StoryGroup] = []
    private(set) var loadedOnce = false
    var error: String?

    func load() async {
        do {
            groups = try await API.shared.rpc("get_story_tray")
            MediaCache.shared.prefetch(groups.flatMap { $0.stories.map(\.media.id) })
            error = nil
        } catch {
            self.error = APIError(error).message
        }
        loadedOnce = true
    }

    func markSeen(storyId: UUID) {
        for g in groups.indices {
            if let s = groups[g].stories.firstIndex(where: { $0.id == storyId }) {
                groups[g].stories[s].seen = true
                groups[g].allSeen = groups[g].stories.allSatisfy(\.seen)
            }
        }
    }

    func removeStory(_ id: UUID) {
        for g in groups.indices { groups[g].stories.removeAll { $0.id == id } }
        groups.removeAll { $0.stories.isEmpty }
    }
}

struct StoryTrayView: View {
    @Environment(AppModel.self) private var appModel
    let model: StoryTrayModel
    @State private var viewing: StoryViewerStart?
    @State private var creating = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.m) {
                if let me = appModel.me, !model.groups.contains(where: { $0.isMine }) {
                    Button { creating = true } label: {
                        TrayItem(profile: me.profile, label: "Your story", unseen: false, isMine: true, addBadge: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to your story")
                }
                ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                    Button {
                        viewing = StoryViewerStart(groupIndex: index)
                    } label: {
                        TrayItem(profile: group.author,
                                 label: group.isMine ? "Your story" : group.author.displayName,
                                 unseen: !group.allSeen, isMine: group.isMine, addBadge: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.isMine ? "Your" : group.author.displayName + "'s") story, \(group.allSeen ? "seen" : "new")")
                    .accessibilityIdentifier("story.\(group.isMine ? "mine" : group.author.id.uuidString)")
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
        .background(Color.cardBackground)
        .fullScreenCover(item: $viewing) { start in
            StoryViewerView(groups: model.groups, startGroup: start.groupIndex, tray: model)
        }
        .fullScreenCover(isPresented: $creating) {
            NavigationStack { CreateStoryView(onPosted: { Task { await model.load() } }) }
        }
    }
}

nonisolated struct StoryViewerStart: Identifiable, Hashable, Sendable {
    let groupIndex: Int
    var id: Int { groupIndex }
}

private struct TrayItem: View {
    let profile: Profile
    let label: String
    let unseen: Bool
    let isMine: Bool
    let addBadge: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(profile: profile, size: 64)
                    .padding(4)
                    .overlay {
                        Circle().strokeBorder(unseen ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: unseen ? 3 : 2)
                    }
                if addBadge {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 76)
                .foregroundStyle(unseen || isMine ? .primary : .secondary)
        }
    }
}
