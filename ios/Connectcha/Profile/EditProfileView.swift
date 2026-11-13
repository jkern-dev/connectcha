import PhotosUI
import SwiftUI

/// Spec 8.2 Edit profile: name, photo, bio (150 characters, A6).
struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var first = ""
    @State private var last = ""
    @State private var bio = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var newAvatarId: UUID?
    @State private var clearAvatar = false
    @State private var saving = false
    @State private var error: String?

    private let bioLimit = 150

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: Spacing.s) {
                            ZStack {
                                if let preview {
                                    Image(uiImage: preview).resizable().scaledToFill()
                                } else if let me = model.me {
                                    AvatarView(profile: clearAvatar ? Profile(id: me.id, firstName: me.firstName, lastName: me.lastName, avatarMediaId: nil) : me.profile, size: 110)
                                }
                            }
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            PhotosPicker("Change photo", selection: $pickerItem, matching: .images)
                            if model.me?.avatarMediaId != nil || preview != nil {
                                Button("Remove photo", role: .destructive) {
                                    preview = nil
                                    newAvatarId = nil
                                    clearAvatar = true
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("First name", text: $first).textContentType(.givenName)
                    TextField("Last name", text: $last).textContentType(.familyName)
                }
                Section {
                    TextField("A few words about you", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.serif(.body)).italic()
                        .onChange(of: bio) { _, new in if new.count > bioLimit { bio = String(new.prefix(bioLimit)) } }
                } header: {
                    Text("A few words")
                } footer: {
                    Text("\(bio.count)/\(bioLimit). Shown to people you've let in.")
                }
                if let error { Section { ErrorText(text: error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .keyboardCanBePutAway()
            .navigationTitle("Your photo and words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || first.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let me = model.me { first = me.firstName; last = me.lastName; bio = me.bio }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        preview = image
                        clearAvatar = false
                        do { newAvatarId = try await MediaUploader.shared.uploadAvatar(image) } catch { self.error = APIError(error).message }
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await API.shared.call("update_profile", UpdateProfileParams(
                pFirstName: first, pLastName: last, pBio: bio, pAvatarMediaId: newAvatarId, pClearAvatar: clearAvatar))
            await model.refreshMe()
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}
