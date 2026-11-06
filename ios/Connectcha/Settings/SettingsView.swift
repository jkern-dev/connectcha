import SwiftUI

/// Spec 10 settings, support email, privacy and terms, sign out (M9 scope,
/// built early because the demo needs sign-out). Demo tools appear only in
/// debug builds with CONNECTCHA_DEMO=1.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = NotificationSettings.allOn
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Toggle("Someone asks to see your photos", isOn: $settings.requests)
                Toggle("Letters and write-backs", isOn: $settings.messages)
                Toggle("Someone finds a photo lovely", isOn: $settings.likes)
                Toggle("People you asked to hear from", isOn: $settings.bells)
            } header: {
                Text("Tell me when")
            } footer: {
                Text("\"People you asked to hear from\" are the people with \"Tell me when they share something\" turned on. Lovelies and who looked at a snapshot never send a notification.")
            }
            .tint(Color.accentColor)
            .onChange(of: settings) { _, new in Task { await save(new) } }

            Section("Help") {
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)?subject=Connectcha")!) {
                    Label("Email support", systemImage: "envelope")
                }
                Text("For problems or questions, email \(AppConfig.supportEmail).")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section("About") {
                Link(destination: AppConfig.privacyURL) { Label("Privacy policy", systemImage: "hand.raised") }
                Link(destination: AppConfig.termsURL) { Label("Terms", systemImage: "doc.text") }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }

            #if DEBUG
            if AppConfig.isDemo {
                Section {
                    NavigationLink("Demo tools") { DemoToolsView() }
                        .accessibilityIdentifier("settings.demoTools")
                } footer: {
                    Text("Only in demo builds.")
                }
            }
            #endif

            Section {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                    .accessibilityIdentifier("settings.signOut")
            }

            Section {
                Button("Delete your account", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("settings.deleteAccount")
                    .disabled(deleting)
            } header: {
                Text("Leaving")
            } footer: {
                Text("Deleting removes your photos, snapshots, your circle and every letter you wrote or received. It can't be undone.")
            }
            if let error { Section { ErrorText(text: error) } }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let me = model.me { settings = me.notificationSettings } }
        .confirmationDialog("Sign out of Connectcha?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text("You'll need a new text code to sign in again.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Your photos, snapshots, your circle and all your letters are deleted for good. People who follow you will no longer see you.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await model.deleteAccount()
        } catch {
            self.error = APIError(error).message
        }
    }

    nonisolated struct SettingsParams: Encodable, Sendable {
        let pRequests: Bool, pMessages: Bool, pLikes: Bool, pBells: Bool
        enum CodingKeys: String, CodingKey { case pRequests = "p_requests", pMessages = "p_messages", pLikes = "p_likes", pBells = "p_bells" }
    }

    private func save(_ s: NotificationSettings) async {
        do {
            try await API.shared.call("update_notification_settings", SettingsParams(pRequests: s.requests, pMessages: s.messages, pLikes: s.likes, pBells: s.bells))
            await model.refreshMe()
        } catch {
            self.error = APIError(error).message
        }
    }
}

#if DEBUG
/// Demo helpers for the scripted walkthrough (D-10, D-11).
struct DemoToolsView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(ContactSync.shared.matches) { person in
                    Button("Delete \"\(person.savedName)\" from Contacts", role: .destructive) {
                        let ok = DemoSeeder.deleteContact(identifier: person.contactIdentifier)
                        message = ok ? "Deleted. Pull to refresh the People tab or reopen the app: their name changes to their profile name and the follow continues." : "Couldn't delete."
                        if ok, let id = model.userId { Task { await ContactSync.shared.run(for: id, force: true) } }
                    }
                }
            } header: {
                Text("Scenario 6: delete a contact")
            } footer: {
                Text("Removes the seeded contact from this simulator's Contacts app.")
            }
            Section("Scenario: matching run") {
                Button("Run contact matching now") {
                    if let id = model.userId { Task { await ContactSync.shared.run(for: id, force: true); message = "Done." } }
                }
                Button("Re-seed this persona's contacts") {
                    UserDefaults.standard.removeObject(forKey: "demo.seededForPhone")
                    if let id = model.userId { Task { await ContactSync.shared.run(for: id, force: true); message = "Re-seeded." } }
                }
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Demo tools")
        .task {
            if ContactSync.shared.matches.isEmpty, let id = model.userId { await ContactSync.shared.run(for: id, force: true) }
        }
    }
}
#endif
