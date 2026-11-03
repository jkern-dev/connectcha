import PhotosUI
import SwiftUI

/// Spec 9.1 steps 2 to 7, in order. Steps 4 to 7 arrive with M3 and M8;
/// until then the flow ends after the photo step.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .name

    enum Step: Int, CaseIterable { case name, photo, contacts, people, invite, notifications }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .name:
                    NameStepView { advance() }
                case .photo:
                    PhotoStepView { advance() }
                case .contacts:
                    ContactsStepView { advance() }
                case .people:
                    PeopleStepView { advance() }
                case .invite:
                    InviteStepView { advance() }
                case .notifications:
                    NotificationsStepView { model.finishOnboarding() }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            // Returning user who already has a name skips straight past it.
            if let me = model.me, me.onboarded, step == .name { step = .photo }
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            model.finishOnboarding()
            return
        }
        withAnimation { step = next }
    }
}

struct NameStepView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void

    @State private var first = ""
    @State private var last = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focus: Field?
    enum Field { case first, last }

    private var canContinue: Bool {
        !first.trimmingCharacters(in: .whitespaces).isEmpty
            && !last.trimmingCharacters(in: .whitespaces).isEmpty
            && !saving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader(
                    title: "What's your name?",
                    subtitle: "People who have your number saved see the name they gave you. Everyone else sees this one."
                )
                .padding(.top, Spacing.l)

                VStack(spacing: Spacing.m) {
                    TextField("First name", text: $first)
                        .textContentType(.givenName)
                        .focused($focus, equals: .first)
                        .submitLabel(.next)
                        .onSubmit { focus = .last }
                        .bigField()
                    TextField("Last name", text: $last)
                        .textContentType(.familyName)
                        .focused($focus, equals: .last)
                        .submitLabel(.done)
                        .bigField()
                }
                .autocorrectionDisabled()

                ErrorText(text: error)

                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().tint(.white) } else { Text("Continue") }
                }
                .buttonStyle(.primary)
                .disabled(!canContinue)
            }
            .padding(Spacing.l)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            if let me = model.me {
                first = me.firstName
                last = me.lastName
            }
            focus = .first
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await API.shared.call("update_profile", UpdateProfileParams(pFirstName: first, pLastName: last))
            await model.refreshMe()
            onDone()
        } catch {
            self.error = APIError(error).message
        }
    }
}

nonisolated struct UpdateProfileParams: Encodable, Sendable {
    var pFirstName: String
    var pLastName: String
    var pBio: String?
    var pAvatarMediaId: UUID?
    var pClearAvatar: Bool = false

    enum CodingKeys: String, CodingKey {
        case pFirstName = "p_first_name"
        case pLastName = "p_last_name"
        case pBio = "p_bio"
        case pAvatarMediaId = "p_avatar_media_id"
        case pClearAvatar = "p_clear_avatar"
    }
}

struct PhotoStepView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                ScreenHeader(
                    title: "A photo of you",
                    subtitle: "It helps people recognise you at the table. You can skip this and add one later."
                )
                .padding(.top, Spacing.l)

                Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                    } else if let me = model.me {
                        AvatarView(profile: me.profile, size: 160)
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(Circle())
                .overlay {
                    if uploading { ProgressView().controlSize(.large) }
                }
                .accessibilityLabel(preview == nil ? "No photo yet" : "Your chosen photo")

                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Text(preview == nil ? "Choose a photo" : "Choose a different photo")
                }
                .buttonStyle(.primary)
                .disabled(uploading)

                ErrorText(text: error)

                Button(preview == nil ? "Skip for now" : "Continue") {
                    onDone()
                }
                .buttonStyle(.secondary)
                .disabled(uploading)
            }
            .padding(Spacing.l)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        error = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                error = "That photo couldn't be read. Please try another."
                return
            }
            preview = image
            let mediaId = try await MediaUploader.shared.uploadAvatar(image)
            try await API.shared.call("update_profile", UpdateProfileParams(
                pFirstName: model.me?.firstName ?? "",
                pLastName: model.me?.lastName ?? "",
                pAvatarMediaId: mediaId
            ))
            await model.refreshMe()
        } catch {
            self.error = APIError(error).message
            preview = nil
        }
    }
}
