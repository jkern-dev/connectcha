import SwiftUI

/// "Past snapshots" (spec 6, keeping stories): every snapshot you posted,
/// still up or gone, visible only to you. Tap to replay, see who looked, save
/// or delete.
struct StoryArchiveView: View {
    @State private var stories: [Story] = []
    @State private var error: String?
    @State private var viewing: Int?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Snapshots you share stay here after they've gone for everyone else. Only you can see this page.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                        Button { viewing = index } label: {
                            PrintFrame(tilt: Tilt.at(index), width: 104, height: 140, label: story.createdAt.formatted(.dateTime.day().month(.abbreviated))) {
                                RemoteImage(mediaId: story.media.id, variant: .thumb)
                            }
                            .overlay(alignment: .topLeading) {
                                if story.expiresAt > Date() {
                                    Text("Still up")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Color.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                        .offset(x: -4, y: -6)
                                }
                            }
                        }
                        .buttonStyle(.cardPress)
                        .accessibilityLabel("Snapshot from \(story.createdAt.formatted(date: .abbreviated, time: .omitted)), \(story.viewCount ?? 0) looked\(story.expiresAt > Date() ? ", active" : "")")
                    }
                }
                .padding(.vertical, Spacing.s)
                if let error { ErrorText(text: error) }
            }
            .padding(Spacing.gutter)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Past snapshots")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: Binding(get: { viewing.map { StoryViewerStart(groupIndex: $0) } }, set: { viewing = $0?.groupIndex })) { start in
            // Each archived snapshot is its own "group" so the progress bar is per snapshot.
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
