import AVKit
import SwiftUI

/// One post as a card on the table (spec 5.2, 5.3): who and when, the photo,
/// a line on the back in italic serif, then "Lovely" and "Write back to X".
struct PostCard: View {
    let post: Post
    var onLike: () -> Void
    var onOpenLikers: (() -> Void)? = nil
    var onOpenPost: (() -> Void)? = nil
    var onMessage: (() -> Void)? = nil
    var onMenu: (() -> Void)? = nil

    @State private var page = 0
    @State private var showBurst = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            mediaPager
            if !post.caption.isEmpty {
                Text(post.caption)
                    .captionSerif(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .card()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.s) {
            NavigationLink(value: ProfileRoute(userId: post.author.id, phoneHash: nil)) {
                HStack(spacing: 10) {
                    AvatarView(profile: post.author, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author.displayName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(metaLine)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let onMenu {
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo options")
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let when = post.publishedAt { parts.append(RelativeTime.string(from: when)) }
        if let place = post.locationName, !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    // MARK: Media

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
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            if showBurst {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(mediaAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.media, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if post.media.count > 1 {
                Text("\(page + 1) of \(post.media.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.printInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.printPaper.opacity(0.92), in: Capsule())
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !post.likedByMe { onLike() }
            withAnimation(.spring(duration: 0.3)) { showBurst = true }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation { showBurst = false }
            }
        }
        .onTapGesture(count: 1) { onOpenPost?() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(post.media.count) \(post.media.count == 1 ? "photo" : "photos") by \(post.author.displayName)\(post.media.count > 1 ? ", swipe sideways for more" : "")")
        .accessibilityHint("Double tap twice quickly to say lovely")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            AdaptiveStack(alignment: .leading, spacing: 10) {
                Button(action: onLike) {
                    Label("Lovely", systemImage: post.likedByMe ? "sun.max.fill" : "sun.max")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.quietPill)
                .accessibilityLabel("Lovely")
                .accessibilityValue(post.likedByMe ? "you said so" : "")
                .accessibilityHint(post.likedByMe ? "Takes it back" : "Tells \(post.author.displayName) you found it lovely")

                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }

                if post.responsesEnabled, !post.isMine, let onMessage {
                    Button("Write back to \(post.author.displayName)", action: onMessage)
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                        .accessibilityHint("A private letter, never a public comment")
                }
            }

            // Anyone sees the count; only the poster can open the list (spec 5.3).
            if post.likeCount > 0 {
                let words = "\(post.likeCount) found it lovely"
                if post.isMine, let onOpenLikers {
                    Button(words, action: onOpenLikers)
                        .buttonStyle(.link)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHint("Shows who")
                        .accessibilityIdentifier("post.likeCount.mine")
                } else {
                    Text(words)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(minHeight: 32)
                        .accessibilityIdentifier("post.likeCount")
                }
            }
        }
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
                        Circle().fill(Palette.printPaper.opacity(0.92)).frame(width: 64, height: 64)
                        if loading { ProgressView().tint(Palette.printInk) } else { Image(systemName: "play.fill").font(.title2).foregroundStyle(Palette.printInk) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
                if let d = item.durationS {
                    Text(durationLabel(d))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.printPaper.opacity(0.92), in: Capsule())
                        .foregroundStyle(Palette.printInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(10)
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
