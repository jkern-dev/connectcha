import Foundation
import Observation

/// Runs the matching pass on every foreground (spec 4.2), keeps the results
/// for the People tab, and maintains the on-device match map.
@MainActor
@Observable
final class ContactSync {
    static let shared = ContactSync()

    private(set) var status: ContactsAccess.Status = ContactsAccess.status()
    private(set) var matches: [MatchedPerson] = []
    private(set) var invites: [InviteCandidate] = []
    /// People who appeared since the previous run; shown as a small prompt.
    var newlyJoined: [MatchedPerson] = []
    private(set) var lastRun: Date?
    private(set) var isRunning = false
    private(set) var lastError: String?

    private var currentUser: UUID?

    private init() {}

    func refreshStatus() {
        status = ContactsAccess.status()
    }

    func requestAccess() async -> ContactsAccess.Status {
        status = await ContactsAccess.request()
        return status
    }

    /// Loads the saved match map for the user so names resolve before the
    /// first network round trip.
    func prepare(for userId: UUID) {
        currentUser = userId
        refreshStatus()
        if status.canRead, let map = MatchMap.load(appGroup: AppConfig.appGroupIdentifier), map.ownerId == userId {
            DisplayNames.shared.update(from: map)
        } else {
            DisplayNames.shared.clear()
        }
    }

    func signedOut() {
        currentUser = nil
        matches = []
        invites = []
        newlyJoined = []
        lastRun = nil
        DisplayNames.shared.clear()
        MatchMap.delete(appGroup: AppConfig.appGroupIdentifier)
    }

    /// The matching run. Safe to call often; it does nothing without access.
    func run(for userId: UUID, force: Bool = false) async {
        currentUser = userId
        refreshStatus()
        if !status.canRead {
            // Without access we no longer know who is in the contacts, so saved
            // names fall back to profile names (D-13) and the map is removed.
            if !matches.isEmpty || !DisplayNames.shared.savedNames.isEmpty {
                matches = []
                invites = []
                DisplayNames.shared.clear()
                MatchMap.delete(appGroup: AppConfig.appGroupIdentifier)
            }
            return
        }
        guard !isRunning else { return }
        if !force, let lastRun, Date().timeIntervalSince(lastRun) < 20 { return }
        isRunning = true
        defer { isRunning = false }

        #if DEBUG
        if AppConfig.isDemo { await DemoSeeder.seedContactsIfNeeded() }
        #endif

        let contacts: [LocalContact]
        do {
            contacts = try await Task.detached(priority: .userInitiated) { try ContactsAccess.readAll() }.value
        } catch {
            lastError = "Couldn't read your contacts."
            return
        }

        do {
            let result = try await ContactMatcher.match(contacts) { hashes in
                try await API.shared.rpc("match_contacts", MatchParams(pHashes: hashes))
            }
            let previous = MatchMap.load(appGroup: AppConfig.appGroupIdentifier) ?? .empty
            let joined = ContactMatcher.newlyJoined(previous: previous, current: result.matches, userId: userId)

            var entries: [UUID: MatchMap.Entry] = [:]
            for m in result.matches {
                entries[m.id] = MatchMap.Entry(contactIdentifier: m.contactIdentifier, savedName: m.savedName)
            }
            let map = MatchMap(ownerId: userId, entries: entries, updatedAt: Date())
            map.save(appGroup: AppConfig.appGroupIdentifier)
            DisplayNames.shared.update(from: map)

            matches = result.matches
            invites = result.invites
            if !joined.isEmpty { newlyJoined = joined }
            lastRun = Date()
            lastError = nil
        } catch {
            lastError = APIError(error).message
        }
    }

    nonisolated struct MatchParams: Encodable, Sendable {
        let pHashes: [String]
        enum CodingKeys: String, CodingKey { case pHashes = "p_hashes" }
    }
}
