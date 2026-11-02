import Foundation
import Observation

/// State behind the People tab and the onboarding people step: incoming
/// requests, outstanding requests, and who you already follow.
@MainActor
@Observable
final class PeopleModel {
    var data = PeopleData(incoming: [], outgoing: [], followingIds: [], followerIds: [])
    var error: String?
    var isLoading = false
    /// Set after an approval when the approver may follow back (spec 3.3 step 3).
    var followBackOffer: Profile?

    nonisolated struct RequestParams: Encodable, Sendable {
        let pTargetId: UUID
        let pTargetPhoneHash: String?
        enum CodingKeys: String, CodingKey { case pTargetId = "p_target_id", pTargetPhoneHash = "p_target_phone_hash" }
    }
    nonisolated struct IdParams: Encodable, Sendable {
        let pRequestId: UUID
        enum CodingKeys: String, CodingKey { case pRequestId = "p_request_id" }
    }

    func load() async {
        isLoading = data.incoming.isEmpty && data.outgoing.isEmpty && data.followingIds.isEmpty
        defer { isLoading = false }
        do {
            data = try await API.shared.rpc("get_people")
            error = nil
        } catch {
            self.error = APIError(error).message
        }
    }

    func state(for userId: UUID) -> PersonState {
        if data.followingIds.contains(userId) { return .following }
        if data.outgoing.contains(where: { $0.targetId == userId }) { return .requested }
        if data.followerIds.contains(userId) { return .followsYou }
        return .none
    }

    enum PersonState { case none, requested, following, followsYou }

    /// People you know (spec 8.5): matched contacts you don't follow yet.
    func peopleYouKnow(from matches: [MatchedPerson]) -> [MatchedPerson] {
        matches.filter { !data.followingIds.contains($0.id) }
    }

    @discardableResult
    func sendRequest(to person: MatchedPerson) async -> Bool {
        do {
            let _: UUID = try await API.shared.rpc("send_follow_request", RequestParams(pTargetId: person.id, pTargetPhoneHash: person.hash))
            await load()
            return true
        } catch {
            self.error = APIError(error).message
            return false
        }
    }

    /// Follow-back request: no number needed because they follow you (spec 3.3).
    @discardableResult
    func sendFollowBack(to userId: UUID) async -> Bool {
        do {
            let _: UUID = try await API.shared.rpc("send_follow_request", RequestParams(pTargetId: userId, pTargetPhoneHash: nil))
            await load()
            return true
        } catch {
            self.error = APIError(error).message
            return false
        }
    }

    func cancelRequest(_ id: UUID) async {
        do {
            try await API.shared.call("cancel_follow_request", IdParams(pRequestId: id))
            await load()
        } catch {
            self.error = APIError(error).message
        }
    }

    func approve(_ request: IncomingRequest) async {
        do {
            let result: ApproveResult = try await API.shared.rpc("approve_follow_request", IdParams(pRequestId: request.id))
            await load()
            if result.followBackAvailable {
                followBackOffer = request.requester
            }
        } catch {
            self.error = APIError(error).message
        }
    }

    func decline(_ request: IncomingRequest) async {
        do {
            try await API.shared.call("decline_follow_request", IdParams(pRequestId: request.id))
            await load()
        } catch {
            self.error = APIError(error).message
        }
    }
}
