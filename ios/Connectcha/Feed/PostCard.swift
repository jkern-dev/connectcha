import AVKit
import SwiftUI

/// One post in the feed or on its own screen (spec 5.2, 5.3).
struct PostCard: View {
    let post: Post
    var onLike: () -> Void
    var onOpenLikers: (() -> Void)? = nil
    var onOpenPost: (() -> Void)? = nil
    var onMessage: (() -> Void)? = nil
    var onMenu: (() -> Void)? = nil

    @State private var page = 0
    @State private var showHeartBurst = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            mediaPager
            actions
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.m)
            }
            if post.responsesEnabled, !post.isMine, let onMessage {
                Button(action: onMessage) {
                    HStack {
                        Image(systemName: "bubble.left")
                        Text("Message \(post.author.displayName)")
                        Spacer()
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 44)
                    .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.m)
                .accessibilityLabel("Message \(post.author.displayName) about this post")
            }
        }
        .padding(.vertical, Spacing.s)
        .background(Color.cardBackground)
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            NavigationLink(value: ProfileRoute(userId: post.author.id, phoneHash: nil)) {
                HStack(spacing: Spacing.s) {
                    AvatarView(profile: post.author, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author.displayName).font(.headline)
                        HStack(spacing: 4) {
                            if let when = post.publishedAt { Text(RelativeTime.string(from: when)) }
                            if let place = post.locationName, !place.isEmpty {
                                Text("·").accessibilityHidden(true)
                                Text(place).lineLimit(1)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let onMenu {
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Post options")
            }
        }
        .padding(.horizontal, Spacing.m)
    }

    private var mediaAspect: CGFloat {
        // Use the first item's ratio for the whole pager; cap very tall media.
        let r = post.media.first?.aspectRatio ?? 1
        return min(max(r, 0.8), 1.91)
    }

    private var mediaPager: some View {
        ZStack {
            if post.media.count == 1, let item = post.media.first {
                MediaView(item: item)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(post.media.enumerated()), id: \.element.id) { index, item in
                        MediaView(item: item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            if showHeartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(mediaAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !post.likedByMe { onLike() }
            withAnimation(.spring(duration: 0.3)) { showHeartBurst = true }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation { showHeartBurst = false }
            }
        }
        .onTapGesture(count: 1) { onOpenPost?() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(post.media.count) \(post.media.count == 1 ? "item" : "items") by \(post.author.displayName)")
        .accessibilityHint("Double tap twice quickly to like")
    }

    private var actions: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onLike) {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(post.likedByMe ? Color.red : Color.primary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.likedByMe ? "Unlike" : "Like")

            // Anyone sees the count; only the poster can open the list (spec 5.3).
            if post.likeCount > 0 {
                let text = Text("\(post.likeCount) like\(post.likeCount == 1 ? "" : "s")").font(.body.weight(.medium))
                if post.isMine, let onOpenLikers {
                    Button(action: onOpenLikers) { text.frame(minHeight: 44) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows who liked your post")
                        .accessibilityIdentifier("post.likeCount.mine")
                } else {
                    text.frame(minHeight: 44).accessibilityIdentifier("post.likeCount")
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.m)
    }
}

/// Photo or video for one media item.
struct MediaView: View {
    let item: MediaItem

    var body: some View {
        switch item.kind {
        case .photo:
            RemoteImage(mediaId: item.id, variant: .full)
        case .video:
            InlineVideoView(item: item)
        }
    }
}

/// Poster thumbnail with a play button; the player is created on demand so
/// scrolling stays cheap and nothing downloads until asked.
struct InlineVideoView: View {
    let item: MediaItem
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        ZStack {
            RemoteImage(mediaId: item.id, variant: .thumb)
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                Button {
                    Task { await start() }
                } label: {
                    ZStack {
                        Circle().fill(.black.opacity(0.55)).frame(width: 72, height: 72)
                        if loading { ProgressView().tint(.white) } else { Image(systemName: "play.fill").font(.title).foregroundStyle(.white) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
                if let d = item.durationS {
                    Text(durationLabel(d))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Spacing.s)
                }
            }
            if failed {
                Text("Couldn't load this video").font(.subheadline).foregroundStyle(.white).padding(8).background(.black.opacity(0.6), in: Capsule())
            }
        }
    }

    private func start() async {
        loading = true
        defer { loading = false }
        guard let urls = await MediaCache.shared.urls(for: item.id) else { failed = true; return }
        let p = AVPlayer(url: urls.url)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
    }

    private func durationLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
