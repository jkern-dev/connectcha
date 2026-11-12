import SwiftUI

/// Spec 6 story tray, shown as "Today's snapshots": your own first (A3), then
/// people with unseen snapshots, most recent first. Ordering comes from the
/// server (get_story_tray) and never depends on who you interact with.
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

/// A small pile of prints, one per person, with "Add yours" at the end. At
/// accessibility text sizes the pile becomes plain rows.
struct SnapshotsSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: StoryTrayModel
    /// Lay the prints out in rows that wrap (the wide, two-page Home) instead
    /// of one row that scrolls sideways.
    var grid = false
    @State private var viewing: StoryViewerStart?
    @State private var creating = false

    private var showAdd: Bool { appModel.me != nil && !model.groups.contains(where: { $0.isMine }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Today's snapshots", note: "gone tomorrow")
                .padding(.horizontal, Spacing.gutter)
            if typeSize.isAccessibilitySize {
                rows
            } else if grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], alignment: .leading, spacing: 18) {
                    prints
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, 10)
            } else {
                pile
            }
        }
        .fullScreenCover(item: $viewing) { start in
            StoryViewerView(groups: model.groups, startGroup: start.groupIndex, tray: model)
        }
        .fullScreenCover(isPresented: $creating) {
            ShareComposerSheet(initialKind: .snapshot, onPublished: { Task { await model.load() } })
        }
    }

    private var pile: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                prints
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var prints: some View {
        ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
            Button {
                viewing = StoryViewerStart(groupIndex: index)
            } label: {
                PrintFrame(tilt: Tilt.at(index), label: group.isMine ? "You" : group.author.displayName) {
                    cover(group)
                }
                .opacity(group.allSeen && !group.isMine ? 0.72 : 1)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel(snapshotLabel(group))
            .accessibilityIdentifier("story.\(group.isMine ? "mine" : group.author.id.uuidString)")
        }
        if showAdd {
            addCard
        }
    }

    private var rows: some View {
        VStack(spacing: Spacing.s) {
            ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                Button {
                    viewing = StoryViewerStart(groupIndex: index)
                } label: {
                    HStack(spacing: Spacing.m) {
                        PrintFrame(width: 64, height: 76) { cover(group) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.isMine ? "You" : group.author.displayName).font(.body.weight(.bold)).foregroundStyle(Palette.ink)
                            Text(group.allSeen ? "seen" : "new · tap to look").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                    }
                    .card()
                }
                .buttonStyle(.cardPress)
                .accessibilityLabel(snapshotLabel(group))
                .accessibilityIdentifier("story.\(group.isMine ? "mine" : group.author.id.uuidString)")
            }
            if showAdd {
                Button { creating = true } label: {
                    Label("Add a snapshot", systemImage: "plus")
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }

    private var addCard: some View {
        Button { creating = true } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                Text("Add yours").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 96, height: 124)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.print, style: .continuous)
                    .strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            )
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Add a snapshot")
        .accessibilityHint("A photo or short video that is gone tomorrow")
    }

    @ViewBuilder
    private func cover(_ group: StoryGroup) -> some View {
        // The first unseen snapshot, else the latest.
        if let story = group.stories.first(where: { !$0.seen }) ?? group.stories.last {
            RemoteImage(mediaId: story.media.id, variant: .thumb)
        } else {
            Color.subtleBackground
        }
    }

    private func snapshotLabel(_ group: StoryGroup) -> String {
        "\(group.isMine ? "Your" : group.author.displayName + "'s") snapshot, \(group.allSeen ? "seen" : "new")"
    }
}

nonisolated struct StoryViewerStart: Identifiable, Hashable, Sendable {
    let groupIndex: Int
    var id: Int { groupIndex }
}
