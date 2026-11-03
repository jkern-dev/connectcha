import SwiftUI

/// An image for a media id. Shows the thumbnail first (fast on slow links),
/// then swaps in the full image when asked for `.full`.
struct RemoteImage: View {
    let mediaId: UUID
    var variant: MediaCache.Variant = .thumb
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.subtleBackground
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .task(id: "\(mediaId)-\(variant)") {
            if let hit = MediaCache.shared.cachedImage(mediaId, variant) {
                image = hit
                return
            }
            if variant == .full, let thumb = MediaCache.shared.cachedImage(mediaId, .thumb) {
                image = thumb
            }
            let loaded = await MediaCache.shared.image(mediaId, variant)
            if let loaded {
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            } else if image == nil {
                failed = true
            }
        }
    }
}

/// Profile photo with an initials fallback (spec 3.1).
struct AvatarView: View {
    let profile: Profile
    var size: CGFloat = 44
    var storyRing = false

    var body: some View {
        ZStack {
            if let id = profile.avatarMediaId {
                RemoteImage(mediaId: id, variant: size > 120 ? .full : .thumb)
            } else {
                Circle().fill(Palette.tint)
                Text(profile.initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.walnutDeep)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            // A thin white border, like a print, instead of a story ring.
            Circle().strokeBorder(Color.white, lineWidth: max(1.5, size * 0.03))
        }
        .overlay(alignment: .bottomTrailing) {
            if storyRing {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: max(10, size * 0.22), weight: .bold))
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(Color.accentColor).padding(-2))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }
}
