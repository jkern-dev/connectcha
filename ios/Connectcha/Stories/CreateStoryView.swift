import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Spec 6 creation: camera or camera roll, text overlay, location, replies
/// toggle. Photos and videos up to 60 seconds.
struct CreateStoryView: View {
    @Environment(\.dismiss) private var dismiss
    var onPosted: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var source: Source?
    @State private var overlayText = ""
    @State private var location: PlaceChoice?
    @State private var repliesEnabled = true
    @State private var showLocation = false
    @State private var showCamera = false
    @State private var posting = false
    @State private var preparing = false
    @State private var status: String?
    @State private var error: String?

    enum Source {
        case photo(UIImage)
        case video(url: URL, preview: UIImage, duration: Double)

        var preview: UIImage {
            switch self {
            case .photo(let i): return i
            case .video(_, let p, _): return p
            }
        }
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                preview
                if source != nil {
                    TextField("Add text (optional)", text: $overlayText, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.body)
                        .padding(Spacing.m)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: overlayText) { _, new in if new.count > 120 { overlayText = String(new.prefix(120)) } }
                        .padding(.horizontal, Spacing.m)
                    HStack {
                        Button { showLocation = true } label: {
                            Label(location?.name ?? "Add a location (optional)", systemImage: "mappin.and.ellipse").lineLimit(1)
                        }
                        .buttonStyle(.quietPill)
                        if location != nil {
                            Button("Remove location", systemImage: "xmark.circle.fill") { location = nil }
                                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.m)
                    Toggle(isOn: $repliesEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow replies")
                            Text("Replies and reactions come to you as private messages.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
                ErrorText(text: error).padding(.horizontal, Spacing.m)
                HStack(spacing: Spacing.s) {
                    PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                        Label(source == nil ? "Camera roll" : "Change", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.secondary)
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.secondary)
                    .disabled(!cameraAvailable)
                }
                .padding(.horizontal, Spacing.m)
                if !cameraAvailable {
                    Text("The camera isn't available on this device. Choose from your camera roll.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, Spacing.m)
                }
                Button {
                    Task { await post() }
                } label: {
                    Text("Share to your story")
                }
                .buttonStyle(.primary)
                .disabled(source == nil || preparing || posting)
                .padding(.horizontal, Spacing.m)
            }
            .padding(.vertical, Spacing.m)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("New story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .sheet(isPresented: $showLocation) { LocationSearchView(selection: $location) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { picked in
                switch picked {
                case .image(let image): source = .photo(image)
                case .video(let url): Task { await prepareVideo(url) }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await prepare(item) }
        }
        .disabled(posting)
        .overlay {
            if posting {
                VStack(spacing: Spacing.m) {
                    ProgressView()
                    Text(status ?? "Sharing…").font(.headline)
                }
                .padding(Spacing.l)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let source {
                Image(uiImage: source.preview)
                    .resizable()
                    .scaledToFit()
                if !overlayText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(overlayText)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, Spacing.l)
                }
                if case .video(_, _, let d) = source {
                    Label(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60), systemImage: "video.fill")
                        .font(.caption.weight(.semibold)).padding(6)
                        .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(Spacing.s)
                }
            } else {
                VStack(spacing: Spacing.s) {
                    if preparing { ProgressView().tint(.white) }
                    Image(systemName: "circle.dashed").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
                    Text("Pick a photo or video").foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .aspectRatio(9 / 14, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Spacing.m)
        .accessibilityLabel(source == nil ? "No media chosen" : "Story preview")
    }

    private func prepare(_ item: PhotosPickerItem) async {
        preparing = true
        error = nil
        defer { preparing = false }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let file = try? await item.loadTransferable(type: MovieFile.self) else { error = "That video couldn't be read."; return }
            await prepareVideo(file.url)
        } else if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            source = .photo(image.normalizedOrientation())
        } else {
            error = "That photo couldn't be read."
        }
    }

    private func prepareVideo(_ url: URL) async {
        do {
            let seconds = try await VideoExporter.duration(of: url)
            guard MediaLimits.videoDurationIsAllowed(seconds) else {
                error = "That video is \(Int(seconds.rounded())) seconds long. Stories can be up to 60 seconds."
                return
            }
            let thumb = try await VideoExporter.thumbnail(of: url)
            source = .video(url: url, preview: UIImage(data: thumb) ?? UIImage(), duration: seconds)
        } catch {
            self.error = "That video couldn't be read."
        }
    }

    nonisolated struct CreateStoryParams: Encodable, Sendable {
        let pMediaId: UUID; let pLocationName: String?; let pRepliesEnabled: Bool
        enum CodingKeys: String, CodingKey { case pMediaId = "p_media_id", pLocationName = "p_location_name", pRepliesEnabled = "p_replies_enabled" }
    }

    private func post() async {
        guard let source else { return }
        posting = true
        error = nil
        defer { posting = false }
        do {
            let mediaId: UUID
            switch source {
            case .photo(let image):
                status = "Preparing photo…"
                let text = overlayText
                let sendable = SendableImage(image)
                let composed = await Task.detached(priority: .userInitiated) { StoryComposer.burn(text: text, into: sendable.image) }.value
                status = "Uploading…"
                mediaId = try await MediaUploader.shared.uploadStoryPhoto(composed)
            case .video(let url, _, let duration):
                status = "Preparing video…"
                let probe = try await VideoExporter.export(url, overlay: nil)
                let overlay = StoryComposer.overlayImage(text: overlayText, size: probe.pixelSize)
                let exported = overlay == nil ? probe : try await VideoExporter.export(url, overlay: overlay)
                let descriptor: MediaDescriptor = try await API.shared.rpc(
                    "create_media", MediaUploader.CreateMediaParams(pUsage: "story", pKind: "video", pDurationS: duration))
                status = "Uploading…"
                try await MediaUploader.shared.uploadVideo(fileURL: exported.fileURL, thumb: exported.thumbnail,
                                                           pixelSize: exported.pixelSize, duration: exported.duration, to: descriptor.id)
                mediaId = descriptor.id
            }
            status = "Sharing…"
            let _: UUID = try await API.shared.rpc("create_story", CreateStoryParams(pMediaId: mediaId, pLocationName: location?.name, pRepliesEnabled: repliesEnabled))
            onPosted()
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}

/// System camera for a photo or a video up to 60 seconds.
struct CameraPicker: UIViewControllerRepresentable {
    enum Picked { case image(UIImage), video(URL) }
    var onPick: (Picked) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoMaximumDuration = MediaLimits.maxVideoSeconds
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Picked) -> Void
        let dismiss: () -> Void
        init(onPick: @escaping (Picked) -> Void, dismiss: @escaping () -> Void) { self.onPick = onPick; self.dismiss = dismiss }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                onPick(.video(url))
            } else if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                onPick(.image(image.normalizedOrientation()))
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}
