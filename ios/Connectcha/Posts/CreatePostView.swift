import AVFoundation
import PhotosUI
import SwiftUI

/// Spec 5.2: 1 to 10 photos or videos (60 s each), a line on the back,
/// a place, and whether people can write back. Upload runs through the media
/// pipeline with progress and retry, then publish.
struct CreatePostView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    var onPublished: () -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var drafts: [DraftItem] = []
    @State private var caption = ""
    @State private var location: PlaceChoice?
    @State private var responsesEnabled = true
    @State private var showLocation = false
    @State private var publishing = false
    @State private var progress: Double = 0
    @State private var status: String?
    @State private var error: String?
    @State private var preparing = false
    private let wide = WideLayout()

    nonisolated struct DraftItem: Identifiable, Sendable {
        let id = UUID()
        enum Payload: Sendable {
            case photo(ImageProcessor.Prepared, preview: SendableImage)
            case video(VideoExporter.Exported, preview: SendableImage)
        }
        let payload: Payload
        var kind: MediaKind { if case .photo = payload { return .photo } else { return .video } }
        var preview: UIImage {
            switch payload {
            case .photo(_, let p): return p.image
            case .video(_, let p): return p.image
            }
        }
        var duration: Double? { if case .video(let v, _) = payload { return v.duration } else { return nil } }
    }

    var body: some View {
        Group {
            if wide.isOn {
                // Unfolded: the prints on the left page, what goes on the
                // back and the Share button on the right.
                TwoPages {
                    ScrollView {
                        photosSection.padding(Spacing.gutter)
                    }
                } right: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.l) { wordsAndShare }
                            .padding(Spacing.gutter)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        photosSection
                        wordsAndShare
                    }
                    .padding(Spacing.gutter)
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLocation) { LocationSearchView(selection: $location) }
        .onChange(of: pickerItems) { _, items in Task { await prepare(items) } }
        .disabled(publishing)
        .overlay {
            if publishing {
                VStack(spacing: Spacing.m) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 220).tint(Color.accentColor)
                    Text(status ?? "Uploading…").font(.body.weight(.semibold))
                }
                .padding(Spacing.l)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var wordsAndShare: some View {
        captionCard
        detailsCard
        ErrorText(text: error)
        Text("Goes to everyone in your circle and nobody else. You can take it off the table any time.")
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        shareButton
    }

    // MARK: Photos

    private var picker: PhotosPicker<some View> {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: MediaLimits.maxItemsPerPost, selectionBehavior: .ordered,
                     matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
            HStack(spacing: Spacing.s) {
                if preparing { ProgressView() } else { Image(systemName: drafts.isEmpty ? "photo.on.rectangle.angled" : "plus") }
                Text(drafts.isEmpty ? "Choose photos or videos" : "Add or change")
            }
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: drafts.isEmpty ? "Your photos" : countTitle, note: "up to 10 · videos up to a minute")
            if drafts.isEmpty {
                picker
                    .buttonStyle(.secondary)
                    .accessibilityHint("Up to 10 items. Videos can be up to 60 seconds.")
            } else if wide.isOn {
                // A page to themselves: larger prints in rows that wrap.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 22) {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        draftPrint(index: index, draft: draft, width: 150, height: 184)
                    }
                }
                .padding(.vertical, 12)
                picker
                    .buttonStyle(.quietPill)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                            draftPrint(index: index, draft: draft, width: 104, height: 128)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                }
                picker
                    .buttonStyle(.quietPill)
            }
        }
    }

    private func draftPrint(index: Int, draft: DraftItem, width: CGFloat, height: CGFloat) -> some View {
        PrintFrame(tilt: Tilt.at(index), width: width, height: height, label: printLabel(index: index, draft: draft)) {
            Image(uiImage: draft.preview)
                .resizable()
                .scaledToFill()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                drafts.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Palette.ink, in: Circle())
            }
            .offset(x: 8, y: -8)
            .accessibilityLabel("Remove \(draft.kind == .video ? "video" : "photo") \(index + 1)")
        }
        .accessibilityLabel("\(draft.kind == .video ? "Video" : "Photo") \(index + 1) of \(drafts.count)")
    }

    private var countTitle: String {
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        let n = drafts.count
        let noun = drafts.allSatisfy { $0.kind == .video } ? (n == 1 ? "video" : "videos") : (n == 1 ? "photo" : "photos")
        return "\(n <= words.count ? words[n - 1] : "\(n)") \(noun)"
    }

    private func printLabel(index: Int, draft: DraftItem) -> String {
        if let d = draft.duration { return String(format: "%d · %d:%02d", index + 1, Int(d) / 60, Int(d) % 60) }
        return index == 0 ? "1 · first" : "\(index + 1)"
    }

    // MARK: Caption and details

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On the back")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Palette.muted)
            TextField("A few words, if you like", text: $caption, axis: .vertical)
                .lineLimit(2...8)
                .font(.serif(.title3))
                .italic()
                .foregroundStyle(Palette.ink)
                .onChange(of: caption) { _, new in if new.count > 1000 { caption = String(new.prefix(1000)) } }
                .accessibilityLabel("A line on the back, optional")
            if caption.count > 800 {
                Text("\(caption.count)/1000").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            Button { showLocation = true } label: {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.accentColor).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(location?.name ?? "A place name, if you like. Never your exact spot.")
                            .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    Spacer()
                    if location != nil {
                        Button("Remove", systemImage: "xmark.circle.fill") { location = nil }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(Palette.muted)
                            .accessibilityLabel("Remove location")
                    } else {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel(location.map { "Where: \($0.name)" } ?? "Where, optional")
            CardDivider()
            Toggle(isOn: $responsesEnabled) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "pencil.line").foregroundStyle(Color.accentColor).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let people write back").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("Replies come to you as letters, never as public comments.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
            }
            .tint(Color.accentColor)
            .padding(16)
        }
        .card(padding: 0)
    }

    private var shareButton: some View {
        Button {
            Task { await publish() }
        } label: {
            Text("Share with your circle")
        }
        .buttonStyle(.primary)
        .disabled(drafts.isEmpty || preparing || publishing)
    }

    // MARK: Preparation

    private func prepare(_ items: [PhotosPickerItem]) async {
        preparing = true
        error = nil
        defer { preparing = false }
        var out: [DraftItem] = []
        for item in items.prefix(MediaLimits.maxItemsPerPost) {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                do {
                    guard let file = try await item.loadTransferable(type: MovieFile.self) else { continue }
                    let exported = try await VideoExporter.export(file.url)
                    let previewImage = UIImage(data: exported.thumbnail) ?? UIImage()
                    out.append(DraftItem(payload: .video(exported, preview: SendableImage(previewImage))))
                } catch VideoExporter.ExportError.tooLong(let s) {
                    error = "One video is \(Int(s.rounded())) seconds long. Videos can be up to 60 seconds."
                } catch {
                    self.error = "One video couldn't be prepared. Try a different one."
                }
            } else if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                let sendable = SendableImage(image)
                if let prepared = await Task.detached(priority: .userInitiated, operation: { ImageProcessor.prepare(sendable.image) }).value {
                    let preview = UIImage(data: prepared.thumb) ?? image
                    out.append(DraftItem(payload: .photo(prepared, preview: SendableImage(preview))))
                }
            }
        }
        drafts = out
    }

    // MARK: Publish

    nonisolated struct CreateParams: Encodable, Sendable {
        let pCaption: String; let pLocationName: String?; let pLocationLat: Double?; let pLocationLng: Double?
        let pResponsesEnabled: Bool; let pMedia: [MediaSpec]
        nonisolated struct MediaSpec: Encodable, Sendable { let kind: String; let durationS: Double?
            enum CodingKeys: String, CodingKey { case kind, durationS = "duration_s" } }
        enum CodingKeys: String, CodingKey {
            case pCaption = "p_caption", pLocationName = "p_location_name", pLocationLat = "p_location_lat"
            case pLocationLng = "p_location_lng", pResponsesEnabled = "p_responses_enabled", pMedia = "p_media"
        }
    }

    private func publish() async {
        publishing = true
        progress = 0
        error = nil
        defer { publishing = false }
        do {
            status = "Getting ready…"
            let specs = drafts.map { CreateParams.MediaSpec(kind: $0.kind.rawValue, durationS: $0.duration) }
            let created: CreatePostResult = try await API.shared.rpc("create_post", CreateParams(
                pCaption: caption, pLocationName: location?.name, pLocationLat: location?.latitude,
                pLocationLng: location?.longitude, pResponsesEnabled: responsesEnabled, pMedia: specs))
            let descriptors = created.media.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            for (index, (draft, descriptor)) in zip(drafts, descriptors).enumerated() {
                status = "Uploading \(index + 1) of \(drafts.count)…"
                switch draft.payload {
                case .photo(let prepared, _):
                    try await MediaUploader.shared.uploadPhoto(prepared, to: descriptor.id)
                case .video(let exported, _):
                    try await MediaUploader.shared.uploadVideo(fileURL: exported.fileURL, thumb: exported.thumbnail,
                                                               pixelSize: exported.pixelSize, duration: exported.duration, to: descriptor.id)
                }
                progress = Double(index + 1) / Double(drafts.count + 1)
            }
            status = "Putting it on the table…"
            try await API.shared.call("publish_post", FeedModel.PostParams(pPostId: created.postId))
            progress = 1
            onPublished()
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}

/// Copies a picked movie into a temporary file for export.
nonisolated struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension))
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}
