import Contacts
import Foundation

/// Reads the address book. Returns `LocalContact` values only; nothing here
/// touches the network.
nonisolated enum ContactsAccess {
    enum Status: Equatable, Sendable {
        case notDetermined, denied, restricted, authorized, limited

        var canRead: Bool { self == .authorized || self == .limited }
    }

    static func status() -> Status {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt (full or limited access on iOS 18).
    static func request() async -> Status {
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        return status()
    }

    /// Every contact with at least one phone number. Saved names are kept only
    /// for display on this device.
    static func readAll() throws -> [LocalContact] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var out: [LocalContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let numbers = contact.phoneNumbers.map { $0.value.stringValue }
            guard !numbers.isEmpty else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.nickname.nonEmpty
                ?? contact.organizationName.nonEmpty
                ?? ""
            guard !name.isEmpty else { return }
            out.append(LocalContact(identifier: contact.identifier, displayName: name, rawNumbers: numbers))
        }
        return out
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
