import ContactsUI
import SwiftUI

/// Spec 8.5 People tab: follow requests, "People you know" (the only
/// discovery surface) and invites. Each person has their own Request button;
/// there is no select-all anywhere (C1).
struct PeopleTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var people = PeopleModel()
    @State private var inviteTarget: InviteCandidate?
    @State private var limitedQuery = ""

    private var sync: ContactSync { ContactSync.shared }

    var body: some View {
        NavigationStack {
            List {
                if !sync.newlyJoined.isEmpty {
                    NewlyJoinedBanner(people: sync.newlyJoined) { sync.newlyJoined = [] }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if !people.data.incoming.isEmpty {
                    Section("Follow requests") {
                        ForEach(people.data.incoming) { request in
                            RequestRow(request: request, people: people)
                        }
                    }
                }

                contactsSection

                if sync.status.canRead {
                    peopleYouKnowSection
                    invitesSection
                }

                if let error = people.error ?? sync.lastError {
                    Section { ErrorText(text: error) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("People")
            .refreshable {
                if let id = appModel.userId { await sync.run(for: id, force: true) }
                await people.load()
                await appModel.refreshUnread()
            }
            .task {
                await people.load()
                if let id = appModel.userId { await sync.run(for: id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let id = appModel.userId {
                    Task { await sync.run(for: id); await people.load() }
                }
            }
            .inviteAction($inviteTarget)
            .followBackPrompt(people: people)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var contactsSection: some View {
        switch sync.status {
        case .notDetermined:
            Section {
                ContactsExplainer(compact: true) {
                    Task {
                        _ = await sync.requestAccess()
                        if let id = appModel.userId { await sync.run(for: id, force: true) }
                    }
                }
            }
        case .denied, .restricted:
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label("Contacts access is off", systemImage: "person.crop.circle.badge.xmark")
                        .font(.headline)
                    Text("Connectcha can only find people through your contacts. You can still approve requests, follow people back and post.")
                        .foregroundStyle(.secondary)
                    Button("Turn on in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.quietPill)
                }
                .padding(.vertical, Spacing.xs)
            }
        case .limited:
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("You've shared some of your contacts. Add more to find more people.")
                        .foregroundStyle(.secondary)
                    TextField("Search your contacts to add", text: $limitedQuery)
                        .textFieldStyle(.roundedBorder)
                    if !limitedQuery.isEmpty {
                        ContactAccessButton(queryString: limitedQuery) { _ in
                            limitedQuery = ""
                            if let id = appModel.userId { Task { await sync.run(for: id, force: true) } }
                        }
                        .frame(minHeight: 44)
                    }
                }
            } header: {
                Text("Contacts")
            }
        case .authorized:
            EmptyView()
        }
    }

    private var peopleYouKnowSection: some View {
        Section {
            let known = people.peopleYouKnow(from: sync.matches)
            if known.isEmpty {
                Text(sync.matches.isEmpty
                     ? "No one from your contacts is on Connectcha yet. Invite someone below."
                     : "You follow everyone from your contacts who is on Connectcha.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(known) { person in
                    PersonRow(person: person, state: people.state(for: person.id)) {
                        Task { await people.sendRequest(to: person) }
                    } onCancel: {
                        if let req = people.data.outgoing.first(where: { $0.targetId == person.id }) {
                            Task { await people.cancelRequest(req.id) }
                        }
                    }
                }
            }
        } header: {
            Text("People you know")
        } footer: {
            Text("People whose number is in your contacts and who are on Connectcha.")
        }
    }

    private var invitesSection: some View {
        Section {
            if sync.invites.isEmpty {
                Text("Everyone in your contacts is already here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sync.invites) { candidate in
                    InviteRow(candidate: candidate) { inviteTarget = candidate }
                }
            }
        } header: {
            Text("Invite to Connectcha")
        } footer: {
            Text("Opens your Messages app with a note you can send. Connectcha never texts anyone for you.")
        }
    }
}

// MARK: - Rows

struct PersonRow: View {
    let person: MatchedPerson
    let state: PeopleModel.PersonState
    var onRequest: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            NavigationLink(value: ProfileRoute(userId: person.id, phoneHash: person.hash)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: person.profile, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.savedName).font(.headline)
                        if state == .followsYou {
                            Text("Follows you").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            switch state {
            case .requested:
                Button("Requested", action: onCancel)
                    .buttonStyle(.quietPill)
                    .accessibilityHint("Tap to cancel your request")
            case .following:
                Text("Following").foregroundStyle(.secondary)
            case .none, .followsYou:
                Button("Request", action: onRequest)
                    .buttonStyle(.pill)
                    .accessibilityLabel("Request to follow \(person.savedName)")
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct InviteRow: View {
    let candidate: InviteCandidate
    var onInvite: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Circle().fill(Color.subtleBackground)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "person").foregroundStyle(.secondary))
                .accessibilityHidden(true)
            Text(candidate.name).font(.body)
            Spacer(minLength: 0)
            Button("Invite", action: onInvite)
                .buttonStyle(.quietPill)
                .accessibilityLabel("Invite \(candidate.name)")
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Spec 3.4: name per 3.2, contacts label, photo. No mutuals hint (C2).
struct RequestRow: View {
    let request: IncomingRequest
    let people: PeopleModel
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            NavigationLink(value: ProfileRoute(userId: request.requester.id, phoneHash: nil)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: request.requester, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.requester.displayName).font(.headline)
                        Text(DisplayNames.shared.contactsLabel(for: request.requester.id))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if request.isFollowBack {
                            Text("\(request.requester.displayName) approved you and wants to follow you back.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: Spacing.s) {
                Button("Approve") { Task { busy = true; await people.approve(request); busy = false } }
                    .buttonStyle(.pill)
                Button("Decline") { Task { busy = true; await people.decline(request); busy = false } }
                    .buttonStyle(.quietPill)
            }
            .disabled(busy)
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct NewlyJoinedBanner: View {
    let people: [MatchedPerson]
    var onDismiss: () -> Void

    private var text: String {
        let names = people.map(\.savedName)
        switch names.count {
        case 1: return "\(names[0]) is now on here"
        case 2: return "\(names[0]) and \(names[1]) are now on here"
        default: return "\(names[0]) and \(names.count - 1) others are now on here"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text(text).font(.body.weight(.medium))
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Navigation target for a person's profile (M4 fills in ProfileView).
nonisolated struct ProfileRoute: Hashable, Sendable {
    let userId: UUID
    let phoneHash: String?
}

// MARK: - Follow-back prompt (spec 3.3 step 3)

struct FollowBackPrompt: ViewModifier {
    let people: PeopleModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            people.followBackOffer.map { "Follow \($0.displayName) back?" } ?? "",
            isPresented: Binding(get: { people.followBackOffer != nil }, set: { if !$0 { people.followBackOffer = nil } }),
            titleVisibility: .visible
        ) {
            if let offer = people.followBackOffer {
                Button("Request to follow \(offer.displayName)") {
                    Task { await people.sendFollowBack(to: offer.id) }
                }
                Button("Not now", role: .cancel) {}
            }
        } message: {
            Text("They'll need to approve before you see their posts.")
        }
    }
}

extension View {
    func followBackPrompt(people: PeopleModel) -> some View { modifier(FollowBackPrompt(people: people)) }
}

/// Spec 9.1 step 4 explanation, reused in the People tab when access was never asked.
struct ContactsExplainer: View {
    var compact = false
    var onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if !compact {
                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            Text(compact ? "Find people you know" : "Find people you know")
                .font(compact ? .headline : .largeTitle.bold())
            VStack(alignment: .leading, spacing: Spacing.s) {
                explainRow("magnifyingglass", "Connectcha looks at the phone numbers in your contacts to find friends and family who are already here.")
                explainRow("iphone", "The names you've saved stay on your phone. They're never sent to us.")
                explainRow("trash", "Numbers of people who aren't on Connectcha aren't kept.")
                explainRow("hand.raised", "Nobody sees your posts unless you approve them.")
            }
            .font(compact ? .subheadline : .body)
            Button("Find people", action: onAllow)
                .buttonStyle(compact ? .quietPill : .pill)
                .padding(.top, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func explainRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 24)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
