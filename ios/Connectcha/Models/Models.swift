import Foundation

// Shapes returned by the read-model functions (supabase/migrations/..._read_models.sql).
// Names here are always *profile* names; DisplayNames swaps in saved contact names.

nonisolated struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let avatarMediaId: UUID?
    var bellOn: Bool?

    var profileName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }
}

nonisolated struct NotificationSettings: Codable, Hashable, Sendable {
    var requests: Bool
    var messages: Bool
    var likes: Bool
    var bells: Bool

    static let allOn = NotificationSettings(requests: true, messages: true, likes: true, bells: true)
}

nonisolated struct Me: Codable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var lastName: String
    var bio: String
    var avatarMediaId: UUID?
    let onboarded: Bool
    let followerCount: Int
    let followingCount: Int
    let pendingRequestCount: Int
    var notificationSettings: NotificationSettings

    var profile: Profile { Profile(id: id, firstName: firstName, lastName: lastName, avatarMediaId: avatarMediaId) }
}

nonisolated enum MediaKind: String, Codable, Hashable, Sendable {
    case photo, video
}

nonisolated struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    let width: Int?
    let height: Int?
    let durationS: Double?
    let position: Int?
    let status: String?

    var aspectRatio: CGFloat {
        guard let w = width, let h = height, w > 0, h > 0 else { return 1 }
        return CGFloat(w) / CGFloat(h)
    }
}

nonisolated struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let author: Profile
    let isMine: Bool
    var caption: String
    var locationName: String?
    var locationLat: Double?
    var locationLng: Double?
    var responsesEnabled: Bool
    let publishedAt: Date?
    let media: [MediaItem]
    var likeCount: Int
    var likedByMe: Bool
}

nonisolated struct FeedPage: Codable, Sendable {
    let posts: [Post]
    let seenThrough: Date?
}

nonisolated struct Story: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let author: Profile
    let isMine: Bool
    let media: MediaItem
    let locationName: String?
    let repliesEnabled: Bool
    let createdAt: Date
    let expiresAt: Date
    var seen: Bool
    let viewCount: Int?
}

nonisolated struct StoryGroup: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { author.id }
    let author: Profile
    let isMine: Bool
    let latestAt: Date
    var allSeen: Bool
    var stories: [Story]
}

nonisolated struct StoryViewer: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { viewer.id }
    let viewer: Profile
    let viewedAt: Date
}

nonisolated struct Relationship: Codable, Hashable, Sendable {
    var iFollow: Bool
    var followsMe: Bool
    var outgoingRequestId: UUID?
    var incomingRequestId: UUID?
    var followBackEligible: Bool
    var bellOn: Bool
    var hasConversation: Bool
}

nonisolated struct ProfileGridItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let publishedAt: Date
    let mediaCount: Int
    let cover: MediaItem?
}

nonisolated struct ProfilePage: Codable, Hashable, Sendable {
    let profile: Profile
    let isMe: Bool
    let canView: Bool
    let bio: String?
    var relationship: Relationship
    let hasActiveStory: Bool
    let posts: [ProfileGridItem]
}

nonisolated struct Connections: Codable, Sendable {
    let followers: [Profile]
    let following: [Profile]
}

nonisolated struct IncomingRequest: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let requester: Profile
    let source: String
    let createdAt: Date

    var isFollowBack: Bool { source == "follow_back" }
}

nonisolated struct OutgoingRequest: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let targetId: UUID
    let source: String
    let createdAt: Date
}

nonisolated struct PeopleData: Codable, Sendable {
    var incoming: [IncomingRequest]
    var outgoing: [OutgoingRequest]
    var followingIds: [UUID]
    var followerIds: [UUID]
}

nonisolated enum MessageKind: String, Codable, Hashable, Sendable {
    case text
    case postResponse = "post_response"
    case storyResponse = "story_response"
    case storyReaction = "story_reaction"
}

nonisolated struct PostPreview: Codable, Hashable, Sendable {
    let id: UUID
    let author: Profile
    let cover: MediaItem?
}

nonisolated struct StoryPreview: Codable, Hashable, Sendable {
    let id: UUID
    let author: Profile
    let media: MediaItem
}

nonisolated struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let kind: MessageKind
    let body: String
    let createdAt: Date
    let post: PostPreview?
    let story: StoryPreview?
}

nonisolated struct InboxItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { conversationId }
    let conversationId: UUID
    let other: Profile
    let lastMessageAt: Date
    let lastMessage: Message?
    var unread: Bool
    let canSend: Bool
}

nonisolated struct ConversationPage: Codable, Sendable {
    let conversationId: UUID
    let other: Profile
    let canSend: Bool
    let messages: [Message]
}

nonisolated struct UnreadCounts: Codable, Sendable {
    let unreadConversations: Int
    let pendingRequests: Int
}

nonisolated enum ActivityType: String, Codable, Hashable, Sendable {
    case followRequest = "follow_request"
    case requestApproved = "request_approved"
    case like
}

nonisolated struct ActivityPostRef: Codable, Hashable, Sendable {
    let id: UUID
    let cover: MediaItem?
}

nonisolated struct ActivityItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let type: ActivityType
    let actor: Profile
    let createdAt: Date
    let requestId: UUID?
    let requestSource: String?
    let requestPending: Bool
    let post: ActivityPostRef?
}

nonisolated struct MediaDescriptor: Codable, Sendable {
    let id: UUID
    let objectKey: String
    let thumbKey: String?
    let position: Int?
    let kind: MediaKind
}

nonisolated struct CreatePostResult: Codable, Sendable {
    let postId: UUID
    let media: [MediaDescriptor]
}

nonisolated struct UploadTarget: Codable, Sendable {
    let mediaId: UUID
    let uploadUrl: URL
    let thumbUploadUrl: URL?
    let contentType: String
}

nonisolated struct UploadTargets: Codable, Sendable {
    let uploads: [UploadTarget]
}

nonisolated struct MediaURLs: Codable, Hashable, Sendable {
    let url: URL
    let thumbUrl: URL?
    let expiresAt: Date
}

nonisolated struct MediaURLBatch: Codable, Sendable {
    let urls: [String: MediaURLs]
    let expiresIn: Int
}

nonisolated struct ApproveResult: Codable, Sendable {
    let requesterId: UUID
    let followBackAvailable: Bool
}

/// A matched contact as returned by match_contacts: the hash we sent plus the
/// person's profile. The saved name is attached on-device, never sent.
nonisolated struct ContactMatch: Codable, Hashable, Sendable {
    let hash: String
    let userId: UUID
    let firstName: String
    let lastName: String
    let avatarMediaId: UUID?

    var profile: Profile { Profile(id: userId, firstName: firstName, lastName: lastName, avatarMediaId: avatarMediaId) }
}

/// What the response and message RPCs return: enough to fetch or append.
nonisolated struct SentMessage: Codable, Sendable {
    let id: UUID
    let conversationId: UUID
    let createdAt: Date
}
