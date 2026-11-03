import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Spec 6 creation, shown as "Snapshot" in the Share sheet: camera or camera
/// roll, a few words on the photo, a place, and whether people can write back.
/// Photos and videos up to 60 seconds.
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
            VStack(alignment: .leading, spacing: Spacing.l) {
                preview
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
                if !cameraAvailable {
                    Text("The camera isn't available on this device. Choose from your camera roll.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if source != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A few words on the photo")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Palette.muted)
                        TextField("Optional", text: $overlayText, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.serif(.title3))
                            .italic()
                            .foregroundStyle(Palette.ink)
                            .onChange(of: overlayText) { _, new in if new.count > 120 { overlayText = String(new.prefix(120)) } }
                            .accessibilityLabel("A few words on the photo, optional")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                    VStack(spacing: 0) {
                        Button { showLocation = true } label: {
                            HStack(spacing: Spacing.m) {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.accentColor).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Where").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                    Text(location?.name ?? "A place name, if you like.").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(2)
                                }
                                Spacer()
                                if location != nil {
                                    Button("Remove location", systemImage: "xmark.circle.fill") { location = nil }
                                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).foregroundStyle(Palette.muted)
                                } else {
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.cardPress)
                        CardDivider()
                        Toggle(isOn: $repliesEnabled) {
                            HStack(spacing: Spacing.m) {
                                Image(systemName: "pencil.line").foregroundStyle(Color.accentColor).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Let people write back").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                    Text("Replies and reactions come to you as letters.").font(.subheadline).foregroundStyle(Palette.muted)
                                }
                            }
                        }
                        .tint(Color.accentColor)
                        .padding(16)
                    }
                    .card(padding: 0)
                }
                ErrorText(text: error)
                Button {
                    Task { await post() }
                } label: {
                    Text("Share today's snapshot")
                }
                .buttonStyle(.primary)
                .disabled(source == nil || preparing || posting)
            }
            .padding(Spacing.gutter)
        }
        .background(Color.appBackground.ignoresSafeArea())
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
                    Text(status ?? "Sharing…").font(.body.weight(.semibold))
                }
                .padding(Spacing.l)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    /// The chosen photo as a print on the table; a dashed outline before.
    private var preview: some View {
        HStack {
            Spacer(minLength: 0)
            Group {
                if let source {
                    PrintFrame(tilt: -1.5, width: 230, height: 300) {
                        ZStack {
                            Image(uiImage: source.preview)
                                .resizable()
                                .scaledToFill()
                            if !overlayText.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(overlayText)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(.horizontal, 12)
                            }
                            if case .video(_, _, let d) = source {
                                Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                                    .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Palette.printPaper.opacity(0.92), in: Capsule()).foregroundStyle(Palette.printInk)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
                            }
                        }
                    }
                    .accessibilityLabel("Snapshot preview")
                } else {
                    VStack(spacing: Spacing.s) {
                        if preparing { ProgressView() }
                        Image(systemName: "photo").font(.title).foregroundStyle(Color.accentColor)
                        Text("Pick a photo or a short video").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .frame(width: 230, height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.print, style: .continuous)
                            .strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    )
                    .accessibilityLabel("No media chosen")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s)
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
                error = "That video is \(Int(seconds.rounded())) seconds long. Snapshots can be up to 60 seconds."
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
