import SwiftUI

/// Spec 8.5 Create (+): new post or story.
struct CreateTab: View {
    var onPublished: () -> Void
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: Spacing.l) {
                Spacer()
                ScreenHeader(title: "What would you like to share?")
                NavigationLink(value: CreatePostRoute()) {
                    CreateChoice(icon: "photo.on.rectangle", title: "New post", detail: "Photos or videos for your feed. Up to 10 at a time.")
                }
                NavigationLink(value: CreateStoryRoute()) {
                    CreateChoice(icon: "circle.dashed", title: "New story", detail: "A photo or video that disappears after 24 hours.")
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(Spacing.l)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Create")
            .navigationDestination(for: CreatePostRoute.self) { _ in
                CreatePostView(onPublished: onPublished)
            }
            .navigationDestination(for: CreateStoryRoute.self) { _ in
                CreateStoryView(onPosted: onPublished)
            }
        }
    }
}

nonisolated struct CreateStoryRoute: Hashable, Sendable {}

struct CreateChoice: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(width: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(Spacing.m)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
