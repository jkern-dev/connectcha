#if DEBUG
import Contacts
import Foundation
import Supabase

/// Demo-only (DECISIONS D-10): writes the signed-in persona's contact list into
/// the simulator's Contacts so matching, names and invites can be shown
/// without hand-typing contacts. Compiled only in DEBUG and active only with
/// CONNECTCHA_DEMO=1. Seeded contacts are tagged with an organisation name so
/// the previous persona's entries can be removed when someone else signs in.
enum DemoSeeder {
    nonisolated static let tag = "Connectcha demo"
    private static let seededKey = "demo.seededForPhone"

    nonisolated struct Entry: Sendable { let name: String; let number: String }

    nonisolated static let personas: [String: [Entry]] = [
        "15550000001": [ // Josh
            Entry(name: "Mom", number: "+1 (555) 000-0002"),
            Entry(name: "Dad", number: "(555) 000-0003"),
            Entry(name: "Ana Silva", number: "555-000-0004"),
            Entry(name: "Priya Nair", number: "+15550000006"),
            Entry(name: "Uncle Mike", number: "(555) 000-0099"),
            Entry(name: "Lucía Fernández", number: "+34 612 345 678"),
        ],
        "15550000002": [ // Mom (Linda)
            Entry(name: "Josh", number: "(555) 000-0001"),
            Entry(name: "Robert", number: "(555) 000-0003"),
            Entry(name: "Priya Nair", number: "(555) 000-0006"),
            Entry(name: "Pastor Jim", number: "(555) 000-0097"),
        ],
        "15550000003": [ // Dad (Robert)
            Entry(name: "Josh", number: "(555) 000-0001"),
            Entry(name: "Linda", number: "(555) 000-0002"),
        ],
        "15550000004": [ // Ana
            Entry(name: "Josh Kern", number: "(555) 000-0001"),
            Entry(name: "Ben Carter", number: "(555) 000-0005"),
            Entry(name: "Priya", number: "(555) 000-0006"),
            Entry(name: "Aunt Carol", number: "(555) 000-0098"),
            Entry(name: "Marco Rossi", number: "+39 333 123 4567"),
        ],
        "15550000005": [ // Ben (does not have Ana)
            Entry(name: "Priya Nair", number: "(555) 000-0006"),
            Entry(name: "Sam Lee", number: "(555) 000-0007"),
            Entry(name: "Coach Dan", number: "(555) 000-0096"),
        ],
        "15550000006": [ // Priya
            Entry(name: "Josh Kern", number: "(555) 000-0001"),
            Entry(name: "Ana Silva", number: "(555) 000-0004"),
            Entry(name: "Ben Carter", number: "(555) 000-0005"),
            Entry(name: "Linda Kern", number: "(555) 000-0002"),
        ],
        "15550000007": [ // Sam
            Entry(name: "Ben Carter", number: "(555) 000-0005"),
        ],
        "15550000008": [ // fresh sign-up
            Entry(name: "Josh Kern", number: "(555) 000-0001"),
            Entry(name: "Ana Silva", number: "(555) 000-0004"),
            Entry(name: "Cousin Dee", number: "(555) 000-0095"),
        ],
        "15550000009": [
            Entry(name: "Josh Kern", number: "(555) 000-0001"),
            Entry(name: "Ana Silva", number: "(555) 000-0004"),
            Entry(name: "Cousin Dee", number: "(555) 000-0095"),
        ],
    ]

    @MainActor
    static func seedContactsIfNeeded() async {
        guard AppConfig.isDemo, ContactsAccess.status().canRead else { return }
        guard let phone = API.shared.client.auth.currentSession?.user.phone, !phone.isEmpty else { return }
        let already = UserDefaults.standard.string(forKey: seededKey)
        guard already != phone else { return }
        let entries = personas[phone] ?? []
        let ok = await Task.detached { replaceSeededContacts(with: entries) }.value
        if ok { UserDefaults.standard.set(phone, forKey: seededKey) }
    }

    /// Removes previously seeded contacts and writes the new list.
    nonisolated private static func replaceSeededContacts(with entries: [Entry]) -> Bool {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        let save = CNSaveRequest()
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if contact.organizationName == tag, let mutable = contact.mutableCopy() as? CNMutableContact {
                    save.delete(mutable)
                }
            }
            for entry in entries {
                let c = CNMutableContact()
                let parts = entry.name.split(separator: " ", maxSplits: 1).map(String.init)
                c.givenName = parts.first ?? entry.name
                c.familyName = parts.count > 1 ? parts[1] : ""
                c.organizationName = tag
                c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: entry.number))]
                save.add(c, toContainerWithIdentifier: nil)
            }
            try store.execute(save)
            return true
        } catch {
            return false
        }
    }

    /// Lets the demo "delete a contact" (S6) from inside the app's debug menu.
    nonisolated static func deleteContact(identifier: String) -> Bool {
        let store = CNContactStore()
        do {
            let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { return false }
            let save = CNSaveRequest()
            save.delete(mutable)
            try store.execute(save)
            return true
        } catch {
            return false
        }
    }
}
#endif
