import Supabase
import Testing
import UIKit
@testable import Connectcha

/// End-to-end post creation against the local stack: create_post → upload →
/// publish, then the post is in the author's feed with resolvable media, and
/// absent for someone who does not follow the author.
@Suite(.serialized)
struct PostPipelineIntegrationTests {
    @MainActor
    @Test("a published post appears in the author's feed and not in a stranger's")
    func publishRoundTrip() async throws {
        guard await MediaPipelineIntegrationTests.stackIsUp() else { return }
        try await TestSignIn.signIn("+15550000009")
        try await API.shared.call("update_profile", UpdateProfileParams(pFirstName: "Pipeline", pLastName: "Tester"))

        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }
        let prepared = try #require(ImageProcessor.prepare(image))

        let created: CreatePostResult = try await API.shared.rpc("create_post", CreatePostView.CreateParams(
            pCaption: "Integration test post", pLocationName: "Test Beach", pLocationLat: 36.9, pLocationLng: -122.0,
            pResponsesEnabled: true, pMedia: [.init(kind: "photo", durationS: nil)]))
        #expect(created.media.count == 1)
        try await MediaUploader.shared.uploadPhoto(prepared, to: created.media[0].id)
        try await API.shared.call("publish_post", FeedModel.PostParams(pPostId: created.postId))

        let feed: FeedPage = try await API.shared.rpc("get_feed", FeedModel.FeedParams(pBefore: nil, pLimit: 20))
        let mine = feed.posts.first { $0.id == created.postId }
        #expect(mine != nil, "own post is in own feed")
        #expect(mine?.caption == "Integration test post")
        #expect(mine?.locationName == "Test Beach")
        let image2 = await MediaCache.shared.image(created.media[0].id, .thumb)
        #expect(image2 != nil, "thumbnail downloads through get-media-urls")

        // Clean up so the demo feed stays as seeded.
        try await API.shared.call("delete_post", FeedModel.PostParams(pPostId: created.postId))
        await TestSignIn.signOut()

        // A stranger (0008) never sees it, nor its media.
        try await TestSignIn.signIn("+15550000008")
        let other: FeedPage = try await API.shared.rpc("get_feed", FeedModel.FeedParams(pBefore: nil, pLimit: 20))
        #expect(!other.posts.contains { $0.id == created.postId })
        let urls = await MediaCache.shared.urls(for: created.media[0].id)
        #expect(urls == nil)
        await TestSignIn.signOut()
    }
}
