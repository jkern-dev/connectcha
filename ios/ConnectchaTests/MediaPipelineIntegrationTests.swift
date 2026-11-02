import Supabase
import Testing
import UIKit
@testable import Connectcha

/// Drives the real client pipeline against the local stack: sign in with a
/// fixed-code number, upload an avatar through create_media → presigned PUT →
/// mark_media_ready, then resolve and download it through get-media-urls.
/// Skipped when the local stack isn't running.
@Suite(.serialized)
struct MediaPipelineIntegrationTests {
    static func stackIsUp() async -> Bool {
        var request = URLRequest(url: AppConfig.supabaseURL.appendingPathComponent("auth/v1/health"))
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @MainActor
    @Test("avatar upload round-trips through the presigned URL pipeline")
    func avatarRoundTrip() async throws {
        guard await Self.stackIsUp() else { return }
        let auth = API.shared.client.auth
        try await auth.signInWithOTP(phone: "+15550000009")
        try await auth.verifyOTP(phone: "+15550000009", token: "123456", type: .sms)
        defer { Task { try? await auth.signOut() } }

        try await API.shared.call("update_profile", UpdateProfileParams(pFirstName: "Pipeline", pLastName: "Tester"))

        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let mediaId = try await MediaUploader.shared.uploadAvatar(image)

        let urls = await MediaCache.shared.urls(for: mediaId)
        #expect(urls != nil, "the uploader's own media must be resolvable")
        let downloaded = await MediaCache.shared.image(mediaId, .full)
        #expect(downloaded != nil)
        #expect(downloaded.map { max($0.pixelSize.width, $0.pixelSize.height) } == 2048, "full image is resized to 2048 px")
        let thumb = await MediaCache.shared.image(mediaId, .thumb)
        #expect(thumb.map { max($0.pixelSize.width, $0.pixelSize.height) } == 400, "thumbnail is 400 px")
    }

    @MainActor
    @Test("a media id the caller may not see resolves to nothing")
    func invisibleMediaIsAbsent() async throws {
        guard await Self.stackIsUp() else { return }
        let auth = API.shared.client.auth
        try await auth.signInWithOTP(phone: "+15550000008")
        try await auth.verifyOTP(phone: "+15550000008", token: "123456", type: .sms)
        defer { Task { try? await auth.signOut() } }
        let urls = await MediaCache.shared.urls(for: UUID())
        #expect(urls == nil)
    }
}
