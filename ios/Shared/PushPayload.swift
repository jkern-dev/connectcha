import Foundation

/// The custom keys send-push puts in every notification. Shared by the app
/// (deep links) and the Notification Service Extension (name rewriting).
nonisolated struct PushPayload: Sendable, Equatable {
    enum Kind: String, Sendable {
        case followRequest = "follow_request"
        case requestApproved = "request_approved"
        case message
        case bellPost = "bell_post"
        case bellStory = "bell_story"
    }

    let kind: Kind
    let actorId: UUID?
    let actorName: String?
    let bodyTemplate: String?
    let requestId: UUID?
    let postId: UUID?
    let storyId: UUID?
    let conversationId: UUID?

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["type"] as? String, let kind = Kind(rawValue: raw) else { return nil }
        self.kind = kind
        actorId = (userInfo["actor_id"] as? String).flatMap(UUID.init)
        actorName = userInfo["actor_name"] as? String
        bodyTemplate = userInfo["body_template"] as? String
        requestId = (userInfo["request_id"] as? String).flatMap(UUID.init)
        postId = (userInfo["post_id"] as? String).flatMap(UUID.init)
        storyId = (userInfo["story_id"] as? String).flatMap(UUID.init)
        conversationId = (userInfo["conversation_id"] as? String).flatMap(UUID.init)
    }

    /// The alert body with the saved contact name swapped in when the sender
    /// is in this phone's contacts (spec 3.2, plan G1). Pure, for testing.
    static func rewrittenBody(template: String?, originalBody: String, actorId: UUID?, savedNames: (UUID) -> String?) -> String {
        guard let template, let actorId, let saved = savedNames(actorId), !saved.isEmpty else { return originalBody }
        return template.replacingOccurrences(of: "{name}", with: saved)
    }
}
