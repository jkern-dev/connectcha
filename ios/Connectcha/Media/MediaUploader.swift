import Foundation
import UIKit

/// Upload pipeline (plan 3.5): create rows → presigned PUT URLs → upload with
/// retry → mark ready. Nothing but bytes and media ids travel.
@MainActor
final class MediaUploader {
    static let shared = MediaUploader()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    nonisolated struct CreateMediaParams: Encodable, Sendable {
        let pUsage: String
        let pKind: String
        let pDurationS: Double?
        enum CodingKeys: String, CodingKey {
            case pUsage = "p_usage", pKind = "p_kind", pDurationS = "p_duration_s"
        }
    }

    nonisolated struct MarkReadyParams: Encodable, Sendable {
        let pMediaId: UUID
        let pWidth: Int
        let pHeight: Int
        let pDurationS: Double?
        let pBytes: Int
        enum CodingKeys: String, CodingKey {
            case pMediaId = "p_media_id", pWidth = "p_width", pHeight = "p_height"
            case pDurationS = "p_duration_s", pBytes = "p_bytes"
        }
    }

    nonisolated struct MediaIds: Encodable, Sendable {
        let mediaIds: [UUID]
        enum CodingKeys: String, CodingKey { case mediaIds = "media_ids" }
    }

    /// Resizes and uploads a profile photo. Returns the media id to store on the profile.
    func uploadAvatar(_ image: UIImage) async throws -> UUID {
        let prepared = try await prepare(image)
        let descriptor: MediaDescriptor = try await API.shared.rpc(
            "create_media", CreateMediaParams(pUsage: "avatar", pKind: "photo", pDurationS: nil))
        try await uploadPhoto(prepared, to: descriptor.id)
        return descriptor.id
    }

    /// Resizes and uploads a story photo. Returns the media id for create_story.
    func uploadStoryPhoto(_ image: UIImage) async throws -> UUID {
        let prepared = try await prepare(image)
        let descriptor: MediaDescriptor = try await API.shared.rpc(
            "create_media", CreateMediaParams(pUsage: "story", pKind: "photo", pDurationS: nil))
        try await uploadPhoto(prepared, to: descriptor.id)
        return descriptor.id
    }

    /// Uploads an already-prepared photo to an existing pending media row.
    func uploadPhoto(_ prepared: ImageProcessor.Prepared, to mediaId: UUID) async throws {
        let targets = try await uploadTargets(for: [mediaId])
        guard let target = targets.first(where: { $0.mediaId == mediaId }) else {
            throw APIError(code: "media_not_found")
        }
        try await put(prepared.full, to: target.uploadUrl, contentType: "image/jpeg")
        if let thumbURL = target.thumbUploadUrl {
            try await put(prepared.thumb, to: thumbURL, contentType: "image/jpeg")
        }
        try await API.shared.call("mark_media_ready", MarkReadyParams(
            pMediaId: mediaId,
            pWidth: Int(prepared.pixelSize.width),
            pHeight: Int(prepared.pixelSize.height),
            pDurationS: nil,
            pBytes: prepared.full.count
        ))
    }

    /// Uploads a transcoded video file plus its thumbnail to a pending media row.
    func uploadVideo(fileURL: URL, thumb: Data, pixelSize: CGSize, duration: Double, to mediaId: UUID,
                     progress: ((Double) -> Void)? = nil) async throws {
        let targets = try await uploadTargets(for: [mediaId])
        guard let target = targets.first(where: { $0.mediaId == mediaId }) else {
            throw APIError(code: "media_not_found")
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        try await putFile(fileURL, to: target.uploadUrl, contentType: "video/mp4", progress: progress)
        if let thumbURL = target.thumbUploadUrl {
            try await put(thumb, to: thumbURL, contentType: "image/jpeg")
        }
        try await API.shared.call("mark_media_ready", MarkReadyParams(
            pMediaId: mediaId,
            pWidth: Int(pixelSize.width),
            pHeight: Int(pixelSize.height),
            pDurationS: duration,
            pBytes: bytes
        ))
    }

    func uploadTargets(for ids: [UUID]) async throws -> [UploadTarget] {
        let result: UploadTargets = try await API.shared.invoke("create-upload-urls", body: MediaIds(mediaIds: ids))
        return result.uploads
    }

    // MARK: - Helpers

    private func prepare(_ image: UIImage) async throws -> ImageProcessor.Prepared {
        let sendable = SendableImage(image)
        let prepared = await Task.detached(priority: .userInitiated) {
            ImageProcessor.prepare(sendable.image)
        }.value
        guard let prepared else { throw APIError(code: "image_unreadable") }
        return prepared
    }

    private func put(_ data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        try await withRetry {
            let (_, response) = try await self.session.upload(for: request, from: data)
            try Self.check(response)
        }
    }

    private func putFile(_ fileURL: URL, to url: URL, contentType: String, progress: ((Double) -> Void)?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        try await withRetry {
            let (_, response) = try await self.session.upload(for: request, fromFile: fileURL)
            try Self.check(response)
            progress?(1)
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(code: "upload_failed", underlying: "\((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
    }

    private func withRetry(attempts: Int = 3, _ work: () async throws -> Void) async throws {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                try await work()
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1) * 1.5))
                }
            }
        }
        throw lastError ?? APIError(code: "upload_failed")
    }
}

/// UIImage is not Sendable; wrapping it is sound here because the image is
/// never mutated after creation.
nonisolated struct SendableImage: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}
