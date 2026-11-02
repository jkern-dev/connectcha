import SwiftUI

/// Spec 6 "Keeping stories": every story you posted, active or expired,
/// visible only to you. Tap to replay, see views, save or delete.
struct StoryArchiveView: View {
    @State private var stories: [Story] = []
    @State private var error: String?
    @State private var viewing: Int?

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            if stories.isEmpty, error == nil {
                Text("Stories you post stay here after they disappear for everyone else.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(Spacing.l)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    Button { viewing = index } label: {
                        Color.clear
                            .aspectRatio(9 / 16, contentMode: .fit)
                            .overlay { RemoteImage(mediaId: story.media.id, variant: .thumb) }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if story.expiresAt > Date() {
                                        Text("Active").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                                    }
                                    Text(story.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2)
                                }
                                .padding(6)
                            }
                            .clipped()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Story from \(story.createdAt.formatted(date: .abbreviated, time: .omitted)), \(story.viewCount ?? 0) views\(story.expiresAt > Date() ? ", active" : "")")
                }
            }
            if let error { ErrorText(text: error).padding() }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Story archive")
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: Binding(get: { viewing.map { StoryViewerStart(groupIndex: $0) } }, set: { viewing = $0?.groupIndex })) { start in
            // Each archived story is its own "group" so the progress bar is per story.
            let groups = stories.map { StoryGroup(author: $0.author, isMine: true, latestAt: $0.createdAt, allSeen: true, stories: [$0]) }
            StoryViewerView(groups: groups, startGroup: start.groupIndex, tray: nil, archiveMode: true)
                .onDisappear { Task { await load() } }
        }
    }

    private func load() async {
        do {
            stories = try await API.shared.rpc("get_my_story_archive")
            error = nil
        } catch {
            self.error = APIError(error).message
        }
    }
}
