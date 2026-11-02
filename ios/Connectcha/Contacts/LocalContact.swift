import Foundation

/// A contact as read from the phone. This type never reaches the networking
/// layer: `ContactMatcher` reduces it to hashes before anything is sent.
nonisolated struct LocalContact: Hashable, Sendable {
    let identifier: String
    let displayName: String
    let rawNumbers: [String]

    /// Normalised numbers, de-duplicated, in the order they were saved.
    var normalized: [PhoneNormalizer.Result] {
        var seen = Set<String>()
        var out: [PhoneNormalizer.Result] = []
        for raw in rawNumbers {
            let result = PhoneNormalizer.normalize(raw)
            let key: String
            switch result {
            case .us(let e): key = e
            case .nonUS(let e): key = e
            case .invalid: continue
            }
            if seen.insert(key).inserted { out.append(result) }
        }
        return out
    }
}

/// A person from the contacts who is on Connectcha (match_contacts result
/// joined back to the local contact).
nonisolated struct MatchedPerson: Hashable, Identifiable, Sendable {
    var id: UUID { profile.id }
    let profile: Profile
    let contactIdentifier: String
    let savedName: String
    /// The hash that matched; sent again as proof when requesting to follow.
    let hash: String
}

/// A contact who is not on Connectcha. Only ever held in memory on the device.
nonisolated struct InviteCandidate: Hashable, Identifiable, Sendable {
    var id: String { contactIdentifier }
    let contactIdentifier: String
    let name: String
    /// The number to text, if US. Non-US contacts stay in the list without one (spec 4.3).
    let usNumber: String?

    var isUS: Bool { usNumber != nil }
}

nonisolated struct MatchResult: Sendable {
    var matches: [MatchedPerson]
    var invites: [InviteCandidate]
    /// Everything that was sent to the server, for the privacy test.
    var hashesSent: [String]
}
