import Foundation

/// Pure matching logic (plan 3.7 "Matching run"): normalise, hash, batch,
/// ask the server which hashes belong to users, and join the answers back to
/// the local contacts. Only hashes cross the wire; the server returns only
/// hashes it was sent.
nonisolated enum ContactMatcher {
    static let batchSize = 500

    typealias Lookup = @Sendable ([String]) async throws -> [ContactMatch]

    static func match(_ contacts: [LocalContact], lookup: Lookup) async throws -> MatchResult {
        // hash -> first contact that holds that number (A5: any of a contact's numbers)
        var hashToContact: [String: LocalContact] = [:]
        var orderedHashes: [String] = []
        var usNumberByContact: [String: String] = [:]
        var hasAnyNumber = Set<String>()

        for contact in contacts {
            for number in contact.normalized {
                switch number {
                case .us(let e164):
                    hasAnyNumber.insert(contact.identifier)
                    if usNumberByContact[contact.identifier] == nil { usNumberByContact[contact.identifier] = e164 }
                    let h = PhoneHasher.hash(e164: e164)
                    if hashToContact[h] == nil {
                        hashToContact[h] = contact
                        orderedHashes.append(h)
                    }
                case .nonUS:
                    hasAnyNumber.insert(contact.identifier)
                case .invalid:
                    break
                }
            }
        }

        var found: [ContactMatch] = []
        for chunk in orderedHashes.chunked(into: batchSize) {
            found += try await lookup(chunk)
        }

        var matches: [MatchedPerson] = []
        var matchedContactIds = Set<String>()
        var seenUsers = Set<UUID>()
        for m in found {
            guard let contact = hashToContact[m.hash], seenUsers.insert(m.userId).inserted else { continue }
            matchedContactIds.insert(contact.identifier)
            matches.append(MatchedPerson(
                profile: m.profile,
                contactIdentifier: contact.identifier,
                savedName: contact.displayName,
                hash: m.hash
            ))
        }

        let invites: [InviteCandidate] = contacts.compactMap { contact in
            guard hasAnyNumber.contains(contact.identifier),
                  !matchedContactIds.contains(contact.identifier),
                  !contact.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return InviteCandidate(
                contactIdentifier: contact.identifier,
                name: contact.displayName,
                usNumber: usNumberByContact[contact.identifier]
            )
        }

        let sorted = matches.sorted { $0.savedName.localizedCaseInsensitiveCompare($1.savedName) == .orderedAscending }
        let sortedInvites = invites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return MatchResult(matches: sorted, invites: sortedInvites, hashesSent: orderedHashes)
    }

    /// Users who appear now but did not appear last time ("Mom is now on here").
    static func newlyJoined(previous: MatchMap, current: [MatchedPerson], userId: UUID) -> [MatchedPerson] {
        guard previous.ownerId == userId else { return [] }   // first run for this user: no prompt
        return current.filter { previous.entries[$0.id] == nil }
    }
}
