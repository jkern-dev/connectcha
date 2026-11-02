import Foundation
import Observation

/// Loads and acts on one person's profile (spec 8.1, 8.3, 3.5).
@MainActor
@Observable
final class ProfileModel {
    let userId: UUID
    /// Proof that the viewer holds the number (from the match list); unlocks
    /// the minimal profile and the Request button for a contact.
    let phoneHash: String?

    var page: ProfilePage?
    var error: String?
    var busy = false
    var followBackOffer: Profile?

    init(userId: UUID, phoneHash: String?) {
        self.userId = userId
        self.phoneHash = phoneHash
    }

    nonisolated struct GetParams: Encodable, Sendable {
        let pUserId: UUID
        let pPhoneHash: String?
        enum CodingKeys: String, CodingKey { case pUserId = "p_user_id", pPhoneHash = "p_phone_hash" }
    }
    nonisolated struct UserParams: Encodable, Sendable {
        let pUserId: UUID
        enum CodingKeys: String, CodingKey { case pUserId = "p_user_id" }
    }
    nonisolated struct BellParams: Encodable, Sendable {
        let pTargetId: UUID
        let pEnabled: Bool
        enum CodingKeys: String, CodingKey { case pTargetId = "p_target_id", pEnabled = "p_enabled" }
    }

    /// Spec 8.3: the Request button appears only when eligible under 3.3.
    var canRequest: Bool {
        guard let r = page?.relationship, !r.iFollow, r.outgoingRequestId == nil else { return false }
        return r.followBackEligible || phoneHash != nil
    }

    func load() async {
        do {
            page = try await API.shared.rpc("get_profile", GetParams(pUserId: userId, pPhoneHash: phoneHash))
            error = nil
        } catch {
            self.error = APIError(error).message
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            await load()
        } catch {
            self.error = APIError(error).message
        }
    }

    func request() async {
        await perform {
            let hash = (page?.relationship.followBackEligible == true && phoneHash == nil) ? nil : phoneHash
            let _: UUID = try await API.shared.rpc("send_follow_request", PeopleModel.RequestParams(pTargetId: userId, pTargetPhoneHash: hash))
        }
    }

    func cancelRequest() async {
        guard let id = page?.relationship.outgoingRequestId else { return }
        await perform { try await API.shared.call("cancel_follow_request", PeopleModel.IdParams(pRequestId: id)) }
    }

    func approveIncoming() async {
        guard let id = page?.relationship.incomingRequestId else { return }
        await perform {
            let result: ApproveResult = try await API.shared.rpc("approve_follow_request", PeopleModel.IdParams(pRequestId: id))
            if result.followBackAvailable, let profile = page?.profile { followBackOffer = profile }
        }
    }

    func declineIncoming() async {
        guard let id = page?.relationship.incomingRequestId else { return }
        await perform { try await API.shared.call("decline_follow_request", PeopleModel.IdParams(pRequestId: id)) }
    }

    func unfollow() async {
        await perform { try await API.shared.call("unfollow", UserParams(pUserId: userId)) }
    }

    func removeFollower() async {
        await perform { try await API.shared.call("remove_follower", UserParams(pUserId: userId)) }
    }

    func setBell(_ on: Bool) async {
        await perform { try await API.shared.call("set_bell", BellParams(pTargetId: userId, pEnabled: on)) }
    }
}
