import Foundation
import Observation
import UIKit

/// Resolves media ids to presigned URLs (batched, cached until shortly before
/// expiry) and caches decoded images in memory. Bytes are cached on disk by
/// URLCache keyed on the full URL, which changes hourly, so the in-memory
/// cache keyed on media id is what makes scrolling back feel instant.
@MainActor
@Observable
final class MediaCache {
    static let shared = MediaCache()

    enum Variant: Hashable { case thumb, full }

    private(set) var urls: [UUID: MediaURLs] = [:]
    private var pending: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<MediaURLs?, Never>]] = [:]
    private var flushScheduled = false

    private let images = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.waitsForConnectivity = true
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    private init() {
        images.countLimit = 400
        images.totalCostLimit = 150 * 1024 * 1024
    }

    static func configureURLCache() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    // MARK: URLs

    /// Signed URLs for a media id, fetching in a batch if needed.
    func urls(for id: UUID) async -> MediaURLs? {
        if let cached = urls[id], cached.expiresAt.timeIntervalSinceNow > 120 {
            return cached
        }
        return await withCheckedContinuation { continuation in
            waiters[id, default: []].append(continuation)
            pending.insert(id)
            scheduleFlush()
        }
    }

    /// Warms the cache for ids about to be shown (feed page, story tray).
    func prefetch(_ ids: [UUID]) {
        for id in ids where !(urls[id].map { $0.expiresAt.timeIntervalSinceNow > 120 } ?? false) {
            pending.insert(id)
        }
        if !pending.isEmpty { scheduleFlush() }
    }

    func forget(_ id: UUID) {
        urls[id] = nil
        images.removeObject(forKey: "\(id)-thumb" as NSString)
        images.removeObject(forKey: "\(id)-full" as NSString)
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(30))
            await flush()
        }
    }

    private func flush() async {
        flushScheduled = false
        let ids = Array(pending)
        pending.removeAll()
        guard !ids.isEmpty else { return }
        for chunk in ids.chunked(into: 100) {
            var batch: MediaURLBatch?
            do {
                batch = try await API.shared.invoke("get-media-urls", body: MediaUploader.MediaIds(mediaIds: chunk))
            } catch {
                batch = nil
            }
            for id in chunk {
                let found = batch?.urls[id.uuidString.lowercased()]
                if let found { urls[id] = found }
                let continuations = waiters.removeValue(forKey: id) ?? []
                for c in continuations { c.resume(returning: found) }
            }
        }
    }

    // MARK: Images

    func cachedImage(_ id: UUID, _ variant: Variant) -> UIImage? {
        images.object(forKey: key(id, variant))
    }

    func image(_ id: UUID, _ variant: Variant) async -> UIImage? {
        if let hit = cachedImage(id, variant) { return hit }
        let k = key(id, variant)
        if let task = inFlight[k as String] { return await task.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            guard let urls = await self.urls(for: id) else { return nil }
            let url = (variant == .thumb ? urls.thumbUrl : nil) ?? urls.url
            return await self.download(url)
        }
        inFlight[k as String] = task
        let image = await task.value
        inFlight[k as String] = nil
        if let image {
            images.setObject(image, forKey: k, cost: Int(image.pixelSize.width * image.pixelSize.height * 4))
        }
        return image
    }

    private func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let bytes = data
        return await Task.detached(priority: .userInitiated) {
            UIImage(data: bytes)?.preparingForDisplay()
        }.value
    }

    private func key(_ id: UUID, _ variant: Variant) -> NSString {
        "\(id)-\(variant == .thumb ? "thumb" : "full")" as NSString
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
