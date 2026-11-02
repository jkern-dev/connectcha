import Foundation
import Testing
@testable import Connectcha

struct FeedTests {
    private func post(_ minutesAgo: Double) -> Post {
        Post(id: UUID(), author: Profile(id: UUID(), firstName: "A", lastName: "B", avatarMediaId: nil), isMine: false,
             caption: "", locationName: nil, locationLat: nil, locationLng: nil, responsesEnabled: true,
             publishedAt: Date(timeIntervalSinceNow: -minutesAgo * 60), media: [], likeCount: 0, likedByMe: false)
    }

    @Test("the caught-up marker sits after the posts newer than the last visit (G7)")
    func caughtUpMarker() {
        let posts = [post(5), post(30), post(120), post(600)]
        #expect(FeedModel.caughtUpIndex(posts: posts, seenThrough: nil) == nil, "first visit: no marker")
        #expect(FeedModel.caughtUpIndex(posts: posts, seenThrough: Date(timeIntervalSinceNow: -60 * 60)) == 2)
        #expect(FeedModel.caughtUpIndex(posts: posts, seenThrough: Date()) == 0, "nothing new: marker at the top")
        #expect(FeedModel.caughtUpIndex(posts: posts, seenThrough: Date(timeIntervalSinceNow: -24 * 3600)) == 4, "everything is new: marker at the end")
        #expect(FeedModel.caughtUpIndex(posts: [], seenThrough: Date()) == nil)
    }

    @Test("video limit allows 60 seconds with rounding slack and refuses 61")
    func videoLimit() {
        #expect(MediaLimits.videoDurationIsAllowed(59.9))
        #expect(MediaLimits.videoDurationIsAllowed(60.0))
        #expect(MediaLimits.videoDurationIsAllowed(60.4))
        #expect(!MediaLimits.videoDurationIsAllowed(61))
        #expect(!MediaLimits.videoDurationIsAllowed(0))
    }

    @Test("relative times read naturally")
    func relativeTime() {
        let now = Date()
        #expect(RelativeTime.string(from: now.addingTimeInterval(-10), now: now) == "Just now")
        #expect(RelativeTime.string(from: now.addingTimeInterval(-5 * 60), now: now) == "5 min ago")
        #expect(RelativeTime.string(from: now.addingTimeInterval(-3600), now: now) == "1 hour ago")
        #expect(RelativeTime.string(from: now.addingTimeInterval(-2 * 86400), now: now) == "2 days ago")
        #expect(RelativeTime.string(from: now.addingTimeInterval(-86400 - 60), now: now) == "Yesterday")
    }
}
