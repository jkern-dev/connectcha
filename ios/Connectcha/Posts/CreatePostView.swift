import AVFoundation
import PhotosUI
import SwiftUI

/// Spec 5.2: 1 to 10 photos or videos (60 s each), optional caption and
/// location, responses toggle. Upload runs through the media pipeline with
/// progress and retry, then publish.
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                picker
                if !drafts.isEmpty { previews }
                captionField
                locationRow
                Toggle(isOn: $responsesEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow responses")
                        Text("Responses are private messages to you, never public comments.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Spacing.m)
                ErrorText(text: error).padding(.horizontal, Spacing.m)
                shareButton
            }
            .padding(.vertical, Spacing.m)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLocation) { LocationSearchView(selection: $location) }
        .onChange(of: pickerItems) { _, items in Task { await prepare(items) } }
        .disabled(publishing)
        .overlay {
            if publishing {
                VStack(spacing: Spacing.m) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 220)
                    Text(status ?? "Uploading…").font(.headline)
                }
                .padding(Spacing.l)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: MediaLimits.maxItemsPerPost, selectionBehavior: .ordered,
                     matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text(drafts.isEmpty ? "Choose photos or videos" : "Change selection")
                Spacer()
                if preparing { ProgressView() }
            }
        }
        .buttonStyle(.secondary)
        .padding(.horizontal, Spacing.m)
        .accessibilityHint("Up to 10 items. Videos can be up to 60 seconds.")
    }

    private var previews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(drafts) { draft in
                    ZStack(alignment: .bottomLeading) {
                        Image(uiImage: draft.preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if let d = draft.duration {
                            Label(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60), systemImage: "video.fill")
                                .font(.caption.weight(.semibold))
                                .padding(6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                    .accessibilityLabel(draft.kind == .video ? "Video" : "Photo")
                }
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Write a caption (optional)", text: $caption, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
                .padding(Spacing.m)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: caption) { _, new in if new.count > 1000 { caption = String(new.prefix(1000)) } }
            Text("\(caption.count)/1000").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.m)
    }

    private var locationRow: some View {
        HStack {
            Button { showLocation = true } label: {
                Label(location?.name ?? "Add a location (optional)", systemImage: "mappin.and.ellipse")
                    .lineLimit(1)
            }
            .buttonStyle(.quietPill)
            if location != nil {
                Button("Remove", systemImage: "xmark.circle.fill") { location = nil }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove location")
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.m)
    }

    private var shareButton: some View {
        Button {
            Task { await publish() }
        } label: {
            Text(drafts.count <= 1 ? "Share" : "Share \(drafts.count) items")
        }
        .buttonStyle(.primary)
        .disabled(drafts.isEmpty || preparing || publishing)
        .padding(.horizontal, Spacing.m)
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
            status = "Creating post…"
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
            status = "Publishing…"
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
