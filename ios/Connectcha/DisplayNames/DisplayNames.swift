import Foundation
import Observation

/// Spec 3.2: a person in your contacts appears under the name you saved,
/// everywhere; otherwise under their profile name. Saved names come from the
/// on-device match map only.
@MainActor
@Observable
final class DisplayNames {
    static let shared = DisplayNames()

    private(set) var savedNames: [UUID: String] = [:]

    private init() {}

    func name(for profile: Profile) -> String {
        savedNames[profile.id] ?? profile.profileName
    }

    func name(for id: UUID, fallback: String) -> String {
        savedNames[id] ?? fallback
    }

    func isInContacts(_ id: UUID) -> Bool { savedNames[id] != nil }

    /// "In your contacts" / "Not in contacts" (spec 3.4).
    func contactsLabel(for id: UUID) -> String {
        isInContacts(id) ? "In your contacts" : "Not in contacts"
    }

    func update(from map: MatchMap) {
        savedNames = map.entries.mapValues(\.savedName)
    }

    func clear() {
        savedNames = [:]
    }
}

extension Profile {
    /// The name to show on screen (saved contact name first).
    @MainActor var displayName: String { DisplayNames.shared.name(for: self) }
    @MainActor var isInContacts: Bool { DisplayNames.shared.isInContacts(id) }
}
