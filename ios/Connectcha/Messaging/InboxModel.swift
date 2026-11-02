import Foundation
import Observation
import Supabase

/// Spec 7: one conversation per pair, started only by a response to a post or
/// story; messages allowed while at least one person follows the other.
@MainActor
@Observable
final class InboxModel {
    private(set) var items: [InboxItem] = []
    private(set) var loadedOnce = false
    var error: String?

    func load() async {
        do {
            items = try await API.shared.rpc("get_inbox")
            MediaCache.shared.prefetch(items.compactMap { $0.other.avatarMediaId })
            error = nil
        } catch {
            self.error = APIError(error).message
        }
        loadedOnce = true
    }
}

@MainActor
@Observable
final class ConversationModel {
    let conversationId: UUID
    private(set) var page: ConversationPage?
    private(set) var messages: [Message] = []
    var draft = ""
    var error: String?
    private(set) var sending = false
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(conversationId: UUID) {
        self.conversationId = conversationId
    }

    nonisolated struct ConversationParams: Encodable, Sendable {
        let pConversationId: UUID
        let pBefore: Date?
        let pLimit: Int
        enum CodingKeys: String, CodingKey { case pConversationId = "p_conversation_id", pBefore = "p_before", pLimit = "p_limit" }
    }
    nonisolated struct IdParams: Encodable, Sendable {
        let pConversationId: UUID
        enum CodingKeys: String, CodingKey { case pConversationId = "p_conversation_id" }
    }
    nonisolated struct SendParams: Encodable, Sendable {
        let pConversationId: UUID
        let pBody: String
        enum CodingKeys: String, CodingKey { case pConversationId = "p_conversation_id", pBody = "p_body" }
    }
    nonisolated struct MessageIdParams: Encodable, Sendable {
        let pMessageId: UUID
        enum CodingKeys: String, CodingKey { case pMessageId = "p_message_id" }
    }

    func load() async {
        do {
            let page: ConversationPage = try await API.shared.rpc("get_conversation", ConversationParams(pConversationId: conversationId, pBefore: nil, pLimit: 50))
            self.page = page
            messages = page.messages
            error = nil
            await markRead()
        } catch {
            self.error = APIError(error).message
        }
    }

    func markRead() async {
        try? await API.shared.call("mark_conversation_read", IdParams(pConversationId: conversationId))
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let sent: SentMessage = try await API.shared.rpc("send_message", SendParams(pConversationId: conversationId, pBody: body))
            if !messages.contains(where: { $0.id == sent.id }),
               let full: Message = try? await API.shared.rpc("get_message", MessageIdParams(pMessageId: sent.id)) {
                messages.append(full)
            }
            draft = ""
            error = nil
        } catch {
            self.error = APIError(error).message
            if APIError(error).code == "conversation_read_only" { await load() }
        }
    }

    /// Realtime: new rows in this conversation (RLS applies to the change feed).
    func startListening() {
        guard channel == nil else { return }
        let ch = API.shared.client.realtimeV2.channel("conversation:\(conversationId.uuidString)")
        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: "conversation_id=eq.\(conversationId.uuidString)")
        channel = ch
        listenTask = Task { [weak self] in
            await ch.subscribe()
            for await insert in inserts {
                guard let self else { return }
                if let idString = insert.record["id"]?.stringValue, let id = UUID(uuidString: idString),
                   !self.messages.contains(where: { $0.id == id }),
                   let full: Message = try? await API.shared.rpc("get_message", MessageIdParams(pMessageId: id)) {
                    self.messages.append(full)
                    await self.markRead()
                }
            }
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }
}
