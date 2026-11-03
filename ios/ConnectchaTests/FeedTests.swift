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

    @Test("the table groups photos under Today, Yesterday, a weekday, then dates")
    func dayGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        // A Tuesday at noon.
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        func at(daysAgo: Int, hour: Int = 9) -> Post {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            return Post(id: UUID(), author: Profile(id: UUID(), firstName: "A", lastName: "B", avatarMediaId: nil), isMine: false,
                        caption: "", locationName: nil, locationLat: nil, locationLng: nil, responsesEnabled: true,
                        publishedAt: date, media: [], likeCount: 0, likedByMe: false)
        }
        let posts = [at(daysAgo: 0, hour: 11), at(daysAgo: 0, hour: 8), at(daysAgo: 1), at(daysAgo: 3), at(daysAgo: 9), at(daysAgo: 400)]
        let groups = FeedModel.dayGroups(posts: posts, now: now, calendar: calendar)
        #expect(groups.map(\.label) == ["Today", "Yesterday", "Saturday", "October 25", "September 29, 2025"])
        #expect(groups.map(\.posts.count) == [2, 1, 1, 1, 1])
        #expect(groups.map(\.startIndex) == [0, 2, 3, 4, 5], "start indexes let the caught-up marker land in the right group")
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
