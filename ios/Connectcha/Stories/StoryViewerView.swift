import AVKit
import Photos
import SwiftUI

/// Full-screen story playback (spec 6): several in a row play in order; tap
/// right or left to move; swipe down to close. Followers can reply or send a
/// quick reaction (both go to the one-to-one conversation); the author sees
/// who viewed, can delete, and can save to the phone.
struct StoryViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let groups: [StoryGroup]
    let startGroup: Int
    var tray: StoryTrayModel?
    var archiveMode = false

    @State private var groupIndex: Int
    @State private var storyIndex = 0
    @State private var progress: Double = 0
    @State private var timer: Task<Void, Never>?
    @State private var player: AVPlayer?
    @State private var paused = false
    @State private var reply = ""
    @State private var showViewers = false
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var replying: Bool

    private let photoSeconds: Double = 5

    init(groups: [StoryGroup], startGroup: Int, tray: StoryTrayModel? = nil, archiveMode: Bool = false) {
        self.groups = groups
        self.startGroup = startGroup
        self.tray = tray
        self.archiveMode = archiveMode
        _groupIndex = State(initialValue: min(startGroup, max(groups.count - 1, 0)))
    }

    private var group: StoryGroup? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }
    private var story: Story? {
        guard let group, group.stories.indices.contains(storyIndex) else { return nil }
        return group.stories[storyIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story, let group {
                media(for: story)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    progressBars(group)
                    header(story)
                    Spacer()
                    footer(story)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                tapZones
            } else {
                Text("No stories").foregroundStyle(.white)
            }
            if let toast {
                Text(toast)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in if v.translation.height > 0 { dragOffset = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { dismiss() } else { withAnimation { dragOffset = 0 } }
                }
        )
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear { start() }
        .onDisappear { stopTimer(); player?.pause() }
        .onChange(of: replying) { _, focused in paused = focused }
        .sheet(isPresented: $showViewers, onDismiss: { paused = false }) {
            if let story { StoryViewersSheet(story: story) }
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteCurrent() } }
        }
        .onChange(of: confirmDelete) { _, open in paused = open }
    }

    // MARK: Pieces

    @ViewBuilder
    private func media(for story: Story) -> some View {
        switch story.media.kind {
        case .photo:
            RemoteImage(mediaId: story.media.id, variant: .full, contentMode: .fit)
        case .video:
            ZStack {
                RemoteImage(mediaId: story.media.id, variant: .thumb, contentMode: .fit)
                if let player {
                    VideoPlayer(player: player)
                        .disabled(true)
                }
            }
        }
    }

    private func progressBars(_ group: StoryGroup) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(group.stories.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.35))
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * (i < storyIndex ? 1 : i == storyIndex ? progress : 0))
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func header(_ story: Story) -> some View {
        HStack(spacing: Spacing.s) {
            AvatarView(profile: story.author, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(story.isMine ? "You" : story.author.displayName).font(.headline).foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(RelativeTime.string(from: story.createdAt))
                    if let place = story.locationName { Text("·").accessibilityHidden(true); Text(place).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            if story.isMine {
                Menu {
                    Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { await saveCurrent() } }
                    Button("Delete story", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Story options")
                .onTapGesture { paused = true }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, Spacing.s)
        .shadow(radius: 4)
    }

    @ViewBuilder
    private func footer(_ story: Story) -> some View {
        if story.isMine {
            Button {
                paused = true
                showViewers = true
            } label: {
                Label(archiveMode ? "\(story.viewCount ?? 0) views" : "Seen by \(story.viewCount ?? 0)", systemImage: "eye")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .padding(.bottom, Spacing.l)
            .accessibilityIdentifier("story.seenBy")
        } else if story.repliesEnabled {
            VStack(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    ForEach(["❤️", "😂", "👏", "😮"], id: \.self) { emoji in
                        Button(emoji) { Task { await send(emoji, reaction: true) } }
                            .font(.title)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(.white.opacity(0.15), in: Capsule())
                            .accessibilityLabel("React \(emoji)")
                    }
                }
                HStack {
                    TextField("Reply to \(story.author.displayName)", text: $reply)
                        .focused($replying)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(.white.opacity(0.18), in: Capsule())
                        .foregroundStyle(.white)
                        .submitLabel(.send)
                        .onSubmit { Task { await send(reply, reaction: false) } }
                    if !reply.isEmpty {
                        Button("Send") { Task { await send(reply, reaction: false) } }
                            .buttonStyle(.pill)
                    }
                }
            }
            .padding(.bottom, Spacing.m)
        } else {
            Text("Replies are off for this story")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, Spacing.l)
        }
    }

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { previous() }
                .accessibilityLabel("Previous story").accessibilityAddTraits(.isButton)
            Color.clear.contentShape(Rectangle()).onTapGesture { next() }
                .accessibilityLabel("Next story").accessibilityAddTraits(.isButton)
        }
        .padding(.top, 90)
        .padding(.bottom, 140)
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in paused = pressing }, perform: {})
    }

    // MARK: Playback

    private func start() {
        guard let story else { return }
        progress = 0
        reply = ""
        player?.pause()
        player = nil
        if !story.isMine, !story.seen {
            Task {
                try? await API.shared.call("mark_story_viewed", StoryParams(pStoryId: story.id))
                tray?.markSeen(storyId: story.id)
            }
        }
        switch story.media.kind {
        case .photo:
            runTimer(seconds: photoSeconds)
        case .video:
            Task {
                guard let urls = await MediaCache.shared.urls(for: story.media.id) else { runTimer(seconds: photoSeconds); return }
                let p = AVPlayer(url: urls.url)
                player = p
                p.play()
                runTimer(seconds: max(story.media.durationS ?? 10, 1), player: p)
            }
        }
    }

    private func runTimer(seconds: Double, player: AVPlayer? = nil) {
        stopTimer()
        timer = Task {
            let tick: Double = 0.05
            var elapsed: Double = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(tick * 1000)))
                if Task.isCancelled { return }
                if paused { player?.pause(); continue }
                if let player, player.rate == 0, player.timeControlStatus != .waitingToPlayAtSpecifiedRate { player.play() }
                if let player {
                    let t = CMTimeGetSeconds(player.currentTime())
                    elapsed = t.isFinite ? t : elapsed
                } else {
                    elapsed += tick
                }
                progress = min(elapsed / seconds, 1)
                if elapsed >= seconds - 0.05 { next(); return }
            }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func next() {
        guard let group else { dismiss(); return }
        if storyIndex + 1 < group.stories.count {
            storyIndex += 1
        } else if groupIndex + 1 < groups.count {
            groupIndex += 1
            storyIndex = 0
        } else {
            dismiss()
            return
        }
        start()
    }

    private func previous() {
        if progress > 0.15 { start(); return }
        if storyIndex > 0 {
            storyIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            storyIndex = max(groups[groupIndex].stories.count - 1, 0)
        }
        start()
    }

    // MARK: Actions

    nonisolated struct StoryParams: Encodable, Sendable {
        let pStoryId: UUID
        enum CodingKeys: String, CodingKey { case pStoryId = "p_story_id" }
    }
    nonisolated struct RespondParams: Encodable, Sendable {
        let pStoryId: UUID; let pBody: String; let pIsReaction: Bool
        enum CodingKeys: String, CodingKey { case pStoryId = "p_story_id", pBody = "p_body", pIsReaction = "p_is_reaction" }
    }

    private func send(_ text: String, reaction: Bool) async {
        guard let story, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let _: SentMessage = try await API.shared.rpc("respond_to_story", RespondParams(pStoryId: story.id, pBody: text, pIsReaction: reaction))
            reply = ""
            replying = false
            show(reaction ? "Sent \(text)" : "Reply sent")
        } catch {
            show(APIError(error).message)
        }
    }

    private func deleteCurrent() async {
        guard let story else { return }
        do {
            try await API.shared.call("delete_story", StoryParams(pStoryId: story.id))
            tray?.removeStory(story.id)
            dismiss()
        } catch {
            show(APIError(error).message)
        }
    }

    private func saveCurrent() async {
        guard let story else { return }
        paused = true
        defer { paused = false }
        guard let urls = await MediaCache.shared.urls(for: story.media.id) else { show("Couldn't load the story"); return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { show("Allow access to Photos in Settings to save stories."); return }
        do {
            let (data, _) = try await URLSession.shared.data(from: urls.url)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (story.media.kind == .video ? ".mp4" : ".jpg"))
            try data.write(to: tmp)
            try await PHPhotoLibrary.shared().performChanges {
                if story.media.kind == .video {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tmp)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tmp)
                }
            }
            show("Saved to Photos")
        } catch {
            show("Couldn't save the story")
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}

/// Only the author sees who viewed (spec 6).
struct StoryViewersSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    @State private var viewers: [StoryViewer] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if viewers.isEmpty, error == nil { Text("Nobody has seen this yet.").foregroundStyle(.secondary) }
                ForEach(viewers) { v in
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: v.viewer, size: 44)
                        Text(v.viewer.displayName)
                        Spacer()
                        Text(RelativeTime.string(from: v.viewedAt)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let error { ErrorText(text: error) }
            }
            .navigationTitle("Seen by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do { viewers = try await API.shared.rpc("get_story_viewers", StoryViewerView.StoryParams(pStoryId: story.id)) }
                catch { self.error = APIError(error).message }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
