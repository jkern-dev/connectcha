import Foundation
import Observation

/// Newest-first feed of the people you follow (spec 5.1) with the
/// "You're all caught up" marker (G7).
@MainActor
@Observable
final class FeedModel {
    private(set) var posts: [Post] = []
    private(set) var seenThrough: Date?
    private(set) var isLoading = false
    private(set) var reachedEnd = false
    var error: String?
    /// Set once the first load finished, so the empty state is not shown while loading.
    private(set) var loadedOnce = false

    private var newestSeenThisVisit: Date?

    nonisolated struct FeedParams: Encodable, Sendable {
        let pBefore: Date?
        let pLimit: Int
        enum CodingKeys: String, CodingKey { case pBefore = "p_before", pLimit = "p_limit" }
    }
    nonisolated struct PostParams: Encodable, Sendable {
        let pPostId: UUID
        enum CodingKeys: String, CodingKey { case pPostId = "p_post_id" }
    }
    nonisolated struct SeenParams: Encodable, Sendable {
        let pThrough: Date
        enum CodingKeys: String, CodingKey { case pThrough = "p_through" }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        do {
            let page: FeedPage = try await API.shared.rpc("get_feed", FeedParams(pBefore: nil, pLimit: 20))
            posts = page.posts
            seenThrough = page.seenThrough
            reachedEnd = page.posts.count < 20
            newestSeenThisVisit = page.posts.first?.publishedAt
            prefetch(page.posts)
            error = nil
        } catch {
            self.error = APIError(error).message
        }
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard !isLoading, !reachedEnd, let last = posts.last, last.id == post.id, let before = last.publishedAt else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page: FeedPage = try await API.shared.rpc("get_feed", FeedParams(pBefore: before, pLimit: 20))
            let known = Set(posts.map(\.id))
            posts += page.posts.filter { !known.contains($0.id) }
            reachedEnd = page.posts.count < 20
            prefetch(page.posts)
        } catch {
            self.error = APIError(error).message
        }
    }

    /// Where to show "You're all caught up": after the last post that is newer
    /// than what the person had seen when they last left the feed.
    nonisolated static func caughtUpIndex(posts: [Post], seenThrough: Date?) -> Int? {
        guard let seenThrough, !posts.isEmpty else { return nil }
        let newer = posts.prefix { ($0.publishedAt ?? .distantPast) > seenThrough }.count
        // Nothing new: the marker sits at the very top.
        return newer
    }

    /// Call when the person leaves the feed (tab switch or background).
    func markSeen() async {
        guard let newest = newestSeenThisVisit else { return }
        if let seenThrough, seenThrough >= newest { return }
        try? await API.shared.call("mark_feed_seen", SeenParams(pThrough: newest))
    }

    func toggleLike(_ post: Post) async {
        guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasLiked = posts[idx].likedByMe
        posts[idx].likedByMe.toggle()
        posts[idx].likeCount += wasLiked ? -1 : 1
        do {
            try await API.shared.call(wasLiked ? "unlike_post" : "like_post", PostParams(pPostId: post.id))
        } catch {
            posts[idx].likedByMe = wasLiked
            posts[idx].likeCount += wasLiked ? 1 : -1
            self.error = APIError(error).message
        }
    }

    func replace(_ post: Post) {
        if let idx = posts.firstIndex(where: { $0.id == post.id }) { posts[idx] = post }
    }

    func remove(postId: UUID) {
        posts.removeAll { $0.id == postId }
    }

    private func prefetch(_ posts: [Post]) {
        let ids = posts.flatMap { p in p.media.map(\.id) + [p.author.avatarMediaId].compactMap { $0 } }
        MediaCache.shared.prefetch(ids)
    }
}

nonisolated enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { let h = Int(seconds / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if seconds < 7 * 86400 { let d = Int(seconds / 86400); return d == 1 ? "Yesterday" : "\(d) days ago" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
