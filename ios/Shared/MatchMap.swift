import Foundation

/// The on-device record of which Connectcha users are in this phone's
/// contacts, and the name saved for each. It lives in the App Group container
/// so the Notification Service Extension can swap saved names into pushes
/// (plan G1). It is never sent anywhere.
nonisolated struct MatchMap: Codable, Sendable, Equatable {
    nonisolated struct Entry: Codable, Hashable, Sendable {
        var contactIdentifier: String
        var savedName: String
    }

    /// The signed-in user this map was built for; a different user starts fresh.
    var ownerId: UUID?
    var entries: [UUID: Entry]
    var updatedAt: Date

    static let empty = MatchMap(ownerId: nil, entries: [:], updatedAt: .distantPast)

    func savedName(for userId: UUID) -> String? { entries[userId]?.savedName }

    // MARK: Persistence

    static func fileURL(appGroup: String) -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("match-map.json")
    }

    static func load(appGroup: String) -> MatchMap? {
        let url = fileURL(appGroup: appGroup)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MatchMap.self, from: data)
    }

    func save(appGroup: String) {
        let url = Self.fileURL(appGroup: appGroup)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func delete(appGroup: String) {
        try? FileManager.default.removeItem(at: fileURL(appGroup: appGroup))
    }
}
