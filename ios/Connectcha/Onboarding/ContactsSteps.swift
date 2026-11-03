import SwiftUI

/// Spec 9.1 step 4: explain, then ask.
struct ContactsStepView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @State private var asked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ContactsExplainer {
                    Task {
                        let status = await ContactSync.shared.requestAccess()
                        asked = true
                        if status.canRead, let id = model.userId {
                            await ContactSync.shared.run(for: id, force: true)
                        }
                        onDone()
                    }
                }
                .padding(.top, Spacing.l)

                Button("Not now") { onDone() }
                    .buttonStyle(.secondary)
                Text("You can turn this on later from People. Without it you can't find anyone, but you can still let people in, follow back and share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            // Already decided on this phone (for example on a reinstall): move on.
            let status = ContactsAccess.status()
            if status != .notDetermined, !asked {
                Task {
                    if status.canRead, let id = model.userId { await ContactSync.shared.run(for: id, force: true) }
                    onDone()
                }
            }
        }
    }
}

/// Spec 9.1 step 5 (C1): a checklist with nothing preselected and one
/// "Send N requests" button. No select-all.
struct PeopleStepView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void

    @State private var people = PeopleModel()
    @State private var selected: Set<UUID> = []
    @State private var sending = false
    @State private var error: String?

    private var sync: ContactSync { ContactSync.shared }
    private var candidates: [MatchedPerson] {
        people.peopleYouKnow(from: sync.matches).filter { people.state(for: $0.id) != .requested }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !sync.status.canRead || (candidates.isEmpty && !sync.isRunning) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        ScreenHeader(
                            title: "People you know",
                            subtitle: sync.status.canRead
                                ? "No one from your contacts is on Connectcha yet. You can invite people next."
                                : "Turn on contacts access from People whenever you like."
                        )
                        .padding(.top, Spacing.l)
                        Button("Continue") { onDone() }.buttonStyle(.primary)
                    }
                    .padding(Spacing.l)
                }
            } else {
                List {
                    Section {
                        ForEach(candidates) { person in
                            Button {
                                if selected.contains(person.id) { selected.remove(person.id) } else { selected.insert(person.id) }
                            } label: {
                                HStack(spacing: Spacing.m) {
                                    Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(selected.contains(person.id) ? Color.accentColor : Color.secondary)
                                    AvatarView(profile: person.profile, size: 48)
                                    Text(person.savedName).font(.headline)
                                    Spacer()
                                }
                                .padding(.vertical, Spacing.xs)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected.contains(person.id) ? .isSelected : [])
                            .accessibilityLabel("\(person.savedName)\(selected.contains(person.id) ? ", selected" : "")")
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("People you know").font(.serif(.largeTitle, weight: .bold)).foregroundStyle(Palette.ink)
                            Text("These people from your contacts are on Connectcha. Tick the ones you'd like to follow. They'll need to say yes.")
                                .font(.body).foregroundStyle(Palette.muted)
                        }
                        .textCase(nil)
                        .padding(.bottom, Spacing.s)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)

                VStack(spacing: Spacing.s) {
                    ErrorText(text: error)
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Text(selected.isEmpty ? "Send requests" : "Send \(selected.count) request\(selected.count == 1 ? "" : "s")")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(selected.isEmpty || sending)
                    Button("Skip for now") { onDone() }
                        .buttonStyle(.secondary)
                }
                .padding(Spacing.l)
                .background(Color.appBackground)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            await people.load()
            if let id = model.userId { await sync.run(for: id) }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        var failed = 0
        for person in candidates where selected.contains(person.id) {
            if !(await people.sendRequest(to: person)) { failed += 1 }
        }
        if failed > 0 {
            error = "Some requests couldn't be sent. You can try again from the People tab."
        }
        onDone()
    }
}

/// Spec 9.1 step 6: invite people, with an easy skip.
struct InviteStepView: View {
    var onDone: () -> Void
    @State private var target: InviteCandidate?

    private var sync: ContactSync { ContactSync.shared }

    var body: some View {
        VStack(spacing: 0) {
            if !sync.status.canRead || sync.invites.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        ScreenHeader(title: "Invite people", subtitle: "You can invite friends and family from People at any time.")
                            .padding(.top, Spacing.l)
                        Button("Continue") { onDone() }.buttonStyle(.primary)
                    }
                    .padding(Spacing.l)
                }
            } else {
                List {
                    Section {
                        ForEach(sync.invites) { candidate in
                            InviteRow(candidate: candidate) { target = candidate }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("Invite people").font(.serif(.largeTitle, weight: .bold)).foregroundStyle(Palette.ink)
                            Text("These contacts aren't on Connectcha yet. Tapping Invite opens your Messages app with a note you can send.")
                                .font(.body).foregroundStyle(Palette.muted)
                        }
                        .textCase(nil)
                        .padding(.bottom, Spacing.s)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                Button("Done") { onDone() }
                    .buttonStyle(.primary)
                    .padding(Spacing.l)
                    .background(Color.appBackground)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .inviteAction($target)
    }
}
