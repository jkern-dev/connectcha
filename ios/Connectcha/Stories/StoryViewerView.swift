import AVKit
import Photos
import SwiftUI

/// Looking at a snapshot (spec 6): one print held up on the paper background,
/// thin progress bars at the top; several in a row play in order; tap right or
/// left to move; swipe down to close. Followers can write back or send a quick
/// reaction (both go to the one-to-one letters); the author sees who looked,
/// can delete, and can save to the phone.
struct StoryViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
            Palette.tint.opacity(0.35).ignoresSafeArea()
            Color.appBackground.opacity(0.9).ignoresSafeArea()
            if let story, let group {
                VStack(spacing: 0) {
                    progressBars(group)
                    header(story)
                    Spacer(minLength: 0)
                    print(for: story)
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        HStack {
                            Text("tap left · previous"); Spacer(); Text("hold · pause"); Spacer(); Text("tap right · next")
                        }
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                    }
                    footer(story)
                }
                .padding(.top, Spacing.s)
                tapZones
            } else {
                Text("No snapshots").foregroundStyle(Palette.muted)
            }
            if let toast {
                Text(toast)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.cardBackground, in: Capsule())
                    .shadow(color: Palette.shadow.opacity(0.15), radius: 4, y: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 130)
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
        .onAppear { start() }
        .onDisappear { stopTimer(); player?.pause() }
        .onChange(of: replying) { _, focused in paused = focused }
        .sheet(isPresented: $showViewers, onDismiss: { paused = false }) {
            if let story { StoryViewersSheet(story: story) }
        }
        .confirmationDialog("Take this snapshot down?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteCurrent() } }
        }
        .onChange(of: confirmDelete) { _, open in paused = open }
    }

    // MARK: Pieces

    private func print(for story: Story) -> some View {
        GeometryReader { geo in
            // The print follows the photo's shape: a landscape photo gets a
            // wide print, a portrait one a tall print, within the room there is.
            let width = min(geo.size.width - 48, 360)
            let captionHeight: CGFloat = story.locationName == nil ? 12 : 34
            let innerWidth = width - 24
            let naturalInner = innerWidth / max(story.media.aspectRatio, 0.01)
            let innerHeight = min(max(naturalInner, innerWidth * 0.7), geo.size.height - 24 - captionHeight)
            let height = innerHeight + 24 + captionHeight
            VStack(spacing: 0) {
                ZStack {
                    media(for: story)
                    if paused && !replying {
                        Image(systemName: "pause.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.printInk)
                            .frame(width: 36, height: 36)
                            .background(Palette.printPaper.opacity(0.9), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(10)
                            .accessibilityLabel("Paused")
                    }
                }
                .frame(width: innerWidth, height: innerHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                if let place = story.locationName {
                    Text(place)
                        .font(.serif(.subheadline)).italic()
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .padding(.top, 8)
                }
            }
            .padding(12)
            .frame(width: width, height: height)
            .background(Palette.printPaper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.22), radius: 14, y: 8)
            .rotationEffect(.degrees(typeSize.isAccessibilitySize ? 0 : -1.2))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(story.isMine ? "Your" : story.author.displayName + "'s") snapshot\(story.locationName.map { ", \($0)" } ?? "")")
    }

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
        HStack(spacing: 6) {
            ForEach(Array(group.stories.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border)
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * (i < storyIndex ? 1 : i == storyIndex ? progress : 0))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .accessibilityHidden(true)
    }

    private func header(_ story: Story) -> some View {
        HStack(spacing: Spacing.s) {
            AvatarView(profile: story.author, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(story.isMine ? "You" : story.author.displayName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(timeLine(story))
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer()
            if story.isMine {
                Menu {
                    Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { await saveCurrent() } }
                    Button("Take it down", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Snapshot options")
                .onTapGesture { paused = true }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 10)
    }

    private func timeLine(_ story: Story) -> String {
        let when = RelativeTime.string(from: story.createdAt)
        if archiveMode {
            return story.expiresAt > Date() ? "\(when) · still up" : when
        }
        let gone = story.expiresAt.formatted(date: .omitted, time: .shortened)
        return "\(when) · gone by \(gone)"
    }

    @ViewBuilder
    private func footer(_ story: Story) -> some View {
        VStack(spacing: Spacing.s) {
            if story.isMine {
                Button {
                    paused = true
                    showViewers = true
                } label: {
                    Label(lookedLabel(story), systemImage: "eye")
                }
                .buttonStyle(.quietPill)
                .accessibilityIdentifier("story.seenBy")
            } else if story.repliesEnabled {
                HStack(spacing: Spacing.s) {
                    ForEach(["❤️", "😂", "👏", "😮"], id: \.self) { emoji in
                        Button(emoji) { Task { await send(emoji, reaction: true) } }
                            .font(.title2)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(Color.cardBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1.5))
                            .accessibilityLabel("React \(emoji)")
                    }
                }
                HStack(spacing: Spacing.s) {
                    TextField("Write back to \(story.author.displayName)…", text: $reply)
                        .focused($replying)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color.cardBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1.5))
                        .foregroundStyle(Palette.ink)
                        .submitLabel(.send)
                        .onSubmit { Task { await send(reply, reaction: false) } }
                    if !reply.isEmpty {
                        Button("Send") { Task { await send(reply, reaction: false) } }
                            .buttonStyle(.pill)
                    }
                }
            } else {
                Text("\(story.author.displayName) turned write-backs off for this one")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func lookedLabel(_ story: Story) -> String {
        let n = story.viewCount ?? 0
        if archiveMode { return "\(n) looked" }
        return n == 0 ? "Nobody has looked yet" : "Looked at by \(n)"
    }

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { previous() }
                .accessibilityLabel("Previous snapshot").accessibilityAddTraits(.isButton)
            Color.clear.contentShape(Rectangle()).onTapGesture { next() }
                .accessibilityLabel("Next snapshot").accessibilityAddTraits(.isButton)
        }
        .padding(.top, 110)
        .padding(.bottom, 150)
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
            show(reaction ? "Sent \(text)" : "Sent as a letter")
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
        guard let urls = await MediaCache.shared.urls(for: story.media.id) else { show("Couldn't load the snapshot"); return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { show("Allow access to Photos in Settings to save snapshots."); return }
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
            show("Couldn't save the snapshot")
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

/// Only the author sees who looked (spec 6).
struct StoryViewersSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    @State private var viewers: [StoryViewer] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if viewers.isEmpty, error == nil { Text("Nobody has looked yet.").foregroundStyle(Palette.muted) }
                ForEach(viewers) { v in
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: v.viewer, size: 44)
                        Text(v.viewer.displayName).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(RelativeTime.string(from: v.viewedAt)).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
                if let error { ErrorText(text: error) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Who looked")
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
