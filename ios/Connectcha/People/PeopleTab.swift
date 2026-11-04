import ContactsUI
import SwiftUI

/// "Your circle": follow requests waiting for your yes, people you know (the
/// only discovery surface) and invites. Each person has their own button;
/// there is no select-all anywhere (C1).
struct PeopleTab: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    /// True when pushed from Home's empty state rather than shown as the tab.
    var embedded = false
    @State private var people = PeopleModel()
    @State private var inviteTarget: InviteCandidate?
    @State private var limitedQuery = ""

    private var sync: ContactSync { ContactSync.shared }

    var body: some View {
        if embedded {
            content.navigationTitle("Your circle").navigationBarTitleDisplayMode(.inline)
        } else {
            NavigationStack {
                content
                    .kitchenTableRoot(title: "People")
                    .appDestinations()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if !embedded {
                    ScreenHeader(title: "Your circle", subtitle: "Only people whose number is in your phone can find you here.")
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, Spacing.s)
                }

                if !sync.newlyJoined.isEmpty {
                    NewlyJoinedBanner(people: sync.newlyJoined) { sync.newlyJoined = [] }
                        .padding(.horizontal, Spacing.gutter)
                }

                if !people.data.incoming.isEmpty {
                    section("Waiting for your yes") {
                        VStack(spacing: Spacing.m) {
                            ForEach(people.data.incoming) { request in
                                RequestRow(request: request, people: people).card(padding: 16)
                            }
                        }
                    }
                }

                contactsSection

                if sync.status.canRead {
                    peopleYouKnowSection
                    invitesSection
                }

                if let error = people.error ?? sync.lastError {
                    ErrorText(text: error).padding(.horizontal, Spacing.gutter)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.appBackground.ignoresSafeArea())
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

    private func section<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title, note: note)
            content()
        }
        .padding(.horizontal, Spacing.gutter)
    }

    // MARK: Sections

    @ViewBuilder
    private var contactsSection: some View {
        switch sync.status {
        case .notDetermined:
            ContactsExplainer(compact: true) {
                Task {
                    _ = await sync.requestAccess()
                    if let id = appModel.userId { await sync.run(for: id, force: true) }
                }
            }
            .card(padding: 16)
            .padding(.horizontal, Spacing.gutter)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Contacts access is off")
                    .font(.body.weight(.semibold))
                Text("Connectcha can only find people through your contacts. You can still say yes to requests, follow people back and share.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.quietPill)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            .padding(.horizontal, Spacing.gutter)
        case .limited:
            section("Contacts") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("You've shared some of your contacts. Add more to find more people.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 16)
            }
        case .authorized:
            EmptyView()
        }
    }

    private var peopleYouKnowSection: some View {
        section("People you know", note: "from your contacts") {
            let known = people.peopleYouKnow(from: sync.matches)
            if known.isEmpty {
                Text(sync.matches.isEmpty
                     ? "No one from your contacts is on Connectcha yet. Invite someone below."
                     : "You follow everyone from your contacts who is on Connectcha.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(known.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { CardDivider() }
                        PersonRow(person: person, state: people.state(for: person.id)) {
                            Task { await people.sendRequest(to: person) }
                        } onCancel: {
                            if let req = people.data.outgoing.first(where: { $0.targetId == person.id }) {
                                Task { await people.cancelRequest(req.id) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private var invitesSection: some View {
        section("Not here yet", note: "opens your Messages") {
            if sync.invites.isEmpty {
                Text("Everyone in your contacts is already here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sync.invites.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { CardDivider() }
                        InviteRow(candidate: candidate) { inviteTarget = candidate }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                .card(padding: 0)
                Text("Connectcha never texts anyone for you; the note is yours to send.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Rows

struct PersonRow: View {
    let person: MatchedPerson
    let state: PeopleModel.PersonState
    var onRequest: () -> Void
    var onCancel: () -> Void
    @State private var confirmCancel = false

    var body: some View {
        AdaptiveStack(alignment: .leading, spacing: Spacing.m) {
            NavigationLink(value: ProfileRoute(userId: person.id, phoneHash: person.hash)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: person.profile, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.savedName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(state == .followsYou ? "Follows you" : "On Connectcha").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            switch state {
            case .requested:
                Button("Asked") { confirmCancel = true }
                    .buttonStyle(.link)
                    .foregroundStyle(Palette.muted)
                    .accessibilityHint("Waiting for their yes. Tap to take the request back.")
                    .confirmationDialog("Take back your request to \(person.savedName)?", isPresented: $confirmCancel, titleVisibility: .visible) {
                        Button("Take it back", role: .destructive, action: onCancel)
                        Button("Keep waiting", role: .cancel) {}
                    }
            case .following:
                Text("Following").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
            case .none, .followsYou:
                Button("Ask to follow", action: onRequest)
                    .buttonStyle(.pill)
                    .accessibilityLabel("Ask to follow \(person.savedName)")
            }
        }
    }
}

struct InviteRow: View {
    let candidate: InviteCandidate
    var onInvite: () -> Void

    var body: some View {
        AdaptiveStack(alignment: .leading, spacing: Spacing.m) {
            Text(candidate.name).font(.body).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button("Invite", action: onInvite)
                .buttonStyle(.quietPill)
                .accessibilityLabel("Invite \(candidate.name)")
        }
    }
}

/// Spec 3.4: name per 3.2, contacts label, photo, and a plain sentence saying
/// what yes means. No mutuals hint (C2).
struct RequestRow: View {
    let request: IncomingRequest
    let people: PeopleModel
    @State private var busy = false

    private var name: String { request.requester.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: ProfileRoute(userId: request.requester.id, phoneHash: nil)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: request.requester, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("\(DisplayNames.shared.contactsLabel(for: request.requester.id)) · asked \(RelativeTime.string(from: request.createdAt).lowercased())")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            Text(request.isFollowBack
                 ? "\(name) let you in and asked to follow you back. Saying yes lets \(name) see your photos and snapshots."
                 : "Saying yes lets \(name) see your photos and snapshots. Nothing is visible until you do.")
                .font(.subheadline)
                .foregroundStyle(Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: Spacing.s) {
                Button("Yes, let \(name) in") { Task { busy = true; await people.approve(request); busy = false } }
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("request.approve")
                Button("Not now") { Task { busy = true; await people.decline(request); busy = false } }
                    .buttonStyle(.quietPill)
                    .accessibilityIdentifier("request.decline")
                    .accessibilityHint("Declines quietly. \(name) is not told.")
            }
            .disabled(busy)
        }
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
        .padding(.vertical, Spacing.xs)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Navigation target for a person's page.
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
                Button("Ask to follow \(offer.displayName)") {
                    Task { await people.sendFollowBack(to: offer.id) }
                }
                Button("Not now", role: .cancel) {}
            }
        } message: {
            Text("They'll need to say yes before you see their photos.")
        }
    }
}

extension View {
    func followBackPrompt(people: PeopleModel) -> some View { modifier(FollowBackPrompt(people: people)) }
}

/// Spec 9.1 step 4 explanation, reused in People when access was never asked.
struct ContactsExplainer: View {
    var compact = false
    var onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if compact {
                Text("Find people you know").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            } else {
                ScreenHeader(title: "Find people you know")
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                explainRow("magnifyingglass", "Connectcha looks at the phone numbers in your contacts to find friends and family who are already here.")
                explainRow("iphone", "The names you've saved stay on your phone. They're never sent to us.")
                explainRow("trash", "Numbers of people who aren't on Connectcha aren't kept.")
                explainRow("hand.raised", "Nobody sees your photos unless you let them in.")
            }
            .font(compact ? .subheadline : .body)
            .foregroundStyle(Palette.body)
            Button("Find people", action: onAllow)
                .buttonStyle(compact ? .quietPill : .pill)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func explainRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 24)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
