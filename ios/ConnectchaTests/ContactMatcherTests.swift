import Foundation
import Testing
@testable import Connectcha

/// S7 and plan 3.6: saved contact names never leave the device, and only
/// hashes are sent. The first test records every byte the API client sends
/// during a full matching run over a fixture address book and asserts that no
/// name and no raw number appears anywhere in any request.
@Suite(.serialized)
struct ContactMatcherTests {
    nonisolated static let fixture: [LocalContact] = [
        LocalContact(identifier: "c-mom", displayName: "Mom", rawNumbers: ["+1 (555) 000-0002"]),
        LocalContact(identifier: "c-dad", displayName: "Dad", rawNumbers: ["(555) 000-0003", "555-000-0103"]),
        LocalContact(identifier: "c-ana", displayName: "Ana Silva", rawNumbers: ["555 000 0004"]),
        LocalContact(identifier: "c-mike", displayName: "Uncle Mike", rawNumbers: ["(555) 000-0099"]),
        LocalContact(identifier: "c-lucia", displayName: "Lucía Fernández", rawNumbers: ["+34 612 345 678"]),
        LocalContact(identifier: "c-empty", displayName: "No Number", rawNumbers: []),
        LocalContact(identifier: "c-short", displayName: "Short Code", rawNumbers: ["911"]),
    ]

    nonisolated static let momHash = PhoneHasher.hash(e164: "+15550000002")
    nonisolated static let anaHash = PhoneHasher.hash(e164: "+15550000004")
    nonisolated static let momId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    nonisolated static let anaId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    nonisolated static func stubResponse() -> Data {
        let json = """
        [
          {"hash":"\(momHash)","user_id":"\(momId.uuidString)","first_name":"Linda","last_name":"Kern","avatar_media_id":null},
          {"hash":"\(anaHash)","user_id":"\(anaId.uuidString)","first_name":"Ana","last_name":"Silva","avatar_media_id":null}
        ]
        """
        return Data(json.utf8)
    }

    @MainActor
    @Test("a full matching run sends hashes only: no saved names, no raw numbers")
    func noNamesOnTheWire() async throws {
        RecordingURLProtocol.start(stubs: [
            .init(pathContains: "/rpc/match_contacts", status: 200, body: Self.stubResponse()),
        ])
        defer { RecordingURLProtocol.stop() }

        let result = try await ContactMatcher.match(Self.fixture) { hashes in
            try await API.shared.rpc("match_contacts", ContactSync.MatchParams(pHashes: hashes))
        }

        let requests = RecordingURLProtocol.recorded
        #expect(!requests.isEmpty, "the run must have talked to the API through the recorded session")

        let forbidden = ["Mom", "Dad", "Ana", "Silva", "Mike", "Uncle", "Lucía", "Lucia", "Fernández", "Fernandez",
                         "5550000002", "555-000-0002", "(555) 000-0002", "5550000003", "5550000004", "5550000099",
                         "34612345678", "612 345 678", "c-mom", "c-dad"]
        for request in requests {
            let blob = request.everything
            for word in forbidden {
                #expect(!blob.localizedCaseInsensitiveContains(word), "request to \(request.url) must not contain \(word)")
            }
        }

        // The body is exactly the hash list.
        let matchRequest = try #require(requests.first { $0.url.contains("match_contacts") })
        let payload = try JSONSerialization.jsonObject(with: Data(matchRequest.body.utf8)) as? [String: Any]
        let sent = try #require(payload?["p_hashes"] as? [String])
        #expect(Set(sent) == Set(result.hashesSent))
        for h in sent {
            #expect(h.count == 64 && h.allSatisfy { $0.isHexDigit }, "only SHA-256 hex strings are sent")
        }
        // Non-US and invalid numbers are never hashed or sent.
        #expect(sent.count == 5, "five distinct US numbers (Mom, both of Dad's, Ana, Uncle Mike) → five hashes")

        // Results join back to the *local* names, on device.
        #expect(result.matches.map(\.savedName) == ["Ana Silva", "Mom"])
        #expect(result.matches.first { $0.id == Self.momId }?.savedName == "Mom")
        #expect(result.matches.first { $0.id == Self.momId }?.profile.profileName == "Linda Kern")
    }

    @Test("invite list: unmatched contacts with numbers; non-US ones have no number to text")
    func invites() async throws {
        let result = try await ContactMatcher.match(Self.fixture) { hashes in
            try JSONDecoder.snake.decode([ContactMatch].self, from: Self.stubResponse())
                .filter { hashes.contains($0.hash) }
        }
        let names = result.invites.map(\.name)
        #expect(names == ["Dad", "Lucía Fernández", "Uncle Mike"])
        #expect(result.invites.first { $0.name == "Uncle Mike" }?.usNumber == "+15550000099")
        #expect(result.invites.first { $0.name == "Lucía Fernández" }?.isUS == false)
        #expect(!names.contains("No Number"), "contacts without a number are not invitable")
        #expect(!names.contains("Short Code"))
    }

    @Test("any of a contact's numbers can match (A5)")
    func anyNumberMatches() async throws {
        let secondNumberHash = PhoneHasher.hash(e164: "+15550000103")
        let json = """
        [{"hash":"\(secondNumberHash)","user_id":"\(UUID().uuidString)","first_name":"Robert","last_name":"Kern","avatar_media_id":null}]
        """
        let result = try await ContactMatcher.match(Self.fixture) { _ in
            try JSONDecoder.snake.decode([ContactMatch].self, from: Data(json.utf8))
        }
        #expect(result.matches.map(\.savedName) == ["Dad"])
    }

    @Test("batches of at most 500 hashes")
    func batching() async throws {
        let many = (0..<1203).map { i in
            LocalContact(identifier: "c\(i)", displayName: "Person \(i)", rawNumbers: [String(format: "415%07d", i)])
        }
        nonisolated(unsafe) var batchSizes: [Int] = []
        let lock = NSLock()
        _ = try await ContactMatcher.match(many) { hashes in
            lock.withLock { batchSizes.append(hashes.count) }
            return []
        }
        #expect(batchSizes == [500, 500, 203])
    }

    @Test("newly joined is empty on the first run, then lists only new people")
    func newlyJoined() {
        let me = UUID()
        let mom = MatchedPerson(profile: Profile(id: Self.momId, firstName: "Linda", lastName: "Kern", avatarMediaId: nil),
                                contactIdentifier: "c-mom", savedName: "Mom", hash: Self.momHash)
        let ana = MatchedPerson(profile: Profile(id: Self.anaId, firstName: "Ana", lastName: "Silva", avatarMediaId: nil),
                                contactIdentifier: "c-ana", savedName: "Ana Silva", hash: Self.anaHash)
        #expect(ContactMatcher.newlyJoined(previous: .empty, current: [mom, ana], userId: me).isEmpty)
        let previous = MatchMap(ownerId: me, entries: [Self.momId: .init(contactIdentifier: "c-mom", savedName: "Mom")], updatedAt: Date())
        #expect(ContactMatcher.newlyJoined(previous: previous, current: [mom, ana], userId: me).map(\.savedName) == ["Ana Silva"])
        let someoneElse = MatchMap(ownerId: UUID(), entries: [:], updatedAt: Date())
        #expect(ContactMatcher.newlyJoined(previous: someoneElse, current: [mom], userId: me).isEmpty, "another user's map never produces prompts")
    }
}

/// Spec 3.2: saved names everywhere, profile name otherwise.
@MainActor
struct DisplayNamesTests {
    @Test func resolution() {
        let names = DisplayNames.shared
        let id = UUID()
        let profile = Profile(id: id, firstName: "Linda", lastName: "Kern", avatarMediaId: nil)
        names.clear()
        #expect(names.name(for: profile) == "Linda Kern")
        #expect(names.contactsLabel(for: id) == "Not in contacts")
        names.update(from: MatchMap(ownerId: UUID(), entries: [id: .init(contactIdentifier: "c", savedName: "Mom")], updatedAt: Date()))
        #expect(names.name(for: profile) == "Mom")
        #expect(names.contactsLabel(for: id) == "In your contacts")
        // S6: removing the contact (next sync drops the entry) falls back to the profile name.
        names.update(from: MatchMap(ownerId: UUID(), entries: [:], updatedAt: Date()))
        #expect(names.name(for: profile) == "Linda Kern")
        names.clear()
    }

    @Test func matchMapRoundTrip() {
        let id = UUID()
        let map = MatchMap(ownerId: id, entries: [id: .init(contactIdentifier: "c", savedName: "Mom")], updatedAt: Date())
        let group = "group.test.\(UUID().uuidString)"
        map.save(appGroup: group)
        let loaded = MatchMap.load(appGroup: group)
        #expect(loaded?.savedName(for: id) == "Mom")
        MatchMap.delete(appGroup: group)
        #expect(MatchMap.load(appGroup: group) == nil)
    }
}

extension JSONDecoder {
    nonisolated(unsafe) static let snake: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
