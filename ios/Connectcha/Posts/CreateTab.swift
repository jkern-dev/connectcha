import SwiftUI

/// What kind of share: photos stay on the table; a snapshot is gone tomorrow.
enum ShareKind: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case snapshot = "Snapshot"
    var id: String { rawValue }
}

/// The Share sheet (spec 8.5 Create): one place for a post or a story,
/// presented from Home's top bar and from "Add yours" in the snapshots pile.
struct ShareComposerSheet: View {
    var initialKind: ShareKind = .photos
    var onPublished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ShareKind
    private let wide = WideLayout()

    init(initialKind: ShareKind = .photos, onPublished: @escaping () -> Void) {
        self.initialKind = initialKind
        self.onPublished = onPublished
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if wide.isOn {
                    // Two pages: the explanation over the photos, the choice
                    // over the words, so the control stays off the fold.
                    HStack(alignment: .center, spacing: 0) {
                        kindNote
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.gutter)
                        kindPicker
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Spacing.gutter)
                    }
                    .padding(.top, Spacing.s)
                    .padding(.bottom, Spacing.xs)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        kindPicker
                        kindNote
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.s)
                    .padding(.bottom, Spacing.xs)
                }
                switch kind {
                case .photos:
                    CreatePostView(onPublished: { onPublished() })
                case .snapshot:
                    CreateStoryView(onPosted: { onPublished() })
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .appDestinations()
        }
        .presentationDragIndicator(.visible)
    }

    private var kindPicker: some View {
        Picker("What kind of share", selection: $kind) {
            ForEach(ShareKind.allCases) { k in Text(k.rawValue).tag(k) }
        }
        .pickerStyle(.segmented)
    }

    private var kindNote: some View {
        Text(kind == .photos
             ? "Photos stay on the table for your circle. Up to 10 at a time."
             : "One photo or short video for today. Gone tomorrow, kept for you.")
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

nonisolated struct CreateStoryRoute: Hashable, Sendable {}
