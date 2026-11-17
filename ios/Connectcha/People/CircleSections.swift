import Observation
import SwiftUI

/// Everyone you follow or who follows you, for People's "In your circle" tab.
/// Each person appears once, grouped by which way the follow goes.
@MainActor
@Observable
final class CircleModel {
    var connections = Connections(followers: [], following: [])
    var hasLoaded = false
    var error: String?

    func load() async {
        do {
            connections = try await API.shared.rpc("get_my_connections")
            error = nil
        } catch {
            self.error = APIError(error).message
        }
        hasLoaded = true
    }

    private var followerIds: Set<UUID> { Set(connections.followers.map(\.id)) }
    private var followingIds: Set<UUID> { Set(connections.following.map(\.id)) }

    var eachOther: [Profile] { sorted(connections.following.filter { followerIds.contains($0.id) }) }
    var followYou: [Profile] { sorted(connections.followers.filter { !followingIds.contains($0.id) }) }
    var youFollow: [Profile] { sorted(connections.following.filter { !followerIds.contains($0.id) }) }
    var totalCount: Int { followerIds.union(followingIds).count }

    func remove(_ person: Profile, as kind: CircleChange) async {
        do {
            try await API.shared.call(kind == .removeFollower ? "remove_follower" : "unfollow", ProfileModel.UserParams(pUserId: person.id))
            await load()
        } catch {
            self.error = APIError(error).message
        }
    }

    private func sorted(_ people: [Profile]) -> [Profile] {
        people.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

enum CircleChange { case removeFollower, unfollow }

/// The groups as list sections. Rows swipe to remove or unfollow (spec 3.5);
/// a tap opens the person's page.
struct CircleSections: View {
    @Environment(AppModel.self) private var appModel
    let circle: CircleModel
    let people: PeopleModel
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var pending: (person: Profile, change: CircleChange)?
    @State private var pendingCancel: (request: OutgoingRequest, name: String)?

    /// Each group shows this many before "Show all".
    private let previewCount = 5
    /// The search field appears once the circle is bigger than this.
    private let searchThreshold = 15

    var body: some View {
        Group {
            if circle.hasLoaded && circle.totalCount == 0 {
                Text("Nobody is in your circle yet. When you say yes to someone, or someone lets you in, they'll appear here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                    .plainListRow()
            } else {
                if circle.totalCount > searchThreshold {
                    searchField.plainListRow()
                }
                group("each", "You follow each other", note: nil, circle.eachOther, changes: [.unfollow, .removeFollower])
                group("followYou", "Follow you", note: "they see your photos", circle.followYou, changes: [.removeFollower])
                group("youFollow", "You follow", note: "you see their photos", circle.youFollow, changes: [.unfollow])
                if circle.hasLoaded {
                    Text("Swipe a name to take someone out of your circle or stop following them. They are not told.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 4)
                        .plainListRow()
                }
            }
            if let error = circle.error {
                ErrorText(text: error).plainListRow()
            }
        }
        .confirmationDialog(
            pending.map { $0.change == .removeFollower ? "Take \($0.person.displayName) out of your circle?" : "Stop following \($0.person.displayName)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(item.change == .removeFollower ? "Remove" : "Unfollow", role: .destructive) {
                Task {
                    await circle.remove(item.person, as: item.change)
                    await people.load()
                    await appModel.refreshMe()
                }
            }
        } message: { item in
            Text(item.change == .removeFollower
                 ? "They'll immediately stop seeing your photos and snapshots. They won't be told."
                 : "You'll stop seeing their photos and snapshots.")
        }
        .confirmationDialog(
            pendingCancel.map { "Take back your request to \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingCancel != nil }, set: { if !$0 { pendingCancel = nil } }),
            titleVisibility: .visible,
            presenting: pendingCancel
        ) { item in
            Button("Take it back", role: .destructive) { Task { await people.cancelRequest(item.request.id) } }
            Button("Keep waiting", role: .cancel) {}
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
            TextField("Search your circle", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityIdentifier("circle.search")
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Palette.muted)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func group(_ id: String, _ title: String, note: String?, _ all: [Profile], changes: [CircleChange]) -> some View {
        let matching = query.isEmpty ? all : all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        let showAll = !query.isEmpty || expanded.contains(id) || matching.count <= previewCount
        let shown = showAll ? matching : Array(matching.prefix(previewCount))
        if !matching.isEmpty {
            Section {
                ForEach(shown) { person in
                    row(person, changes: changes)
                }
                if matching.count > previewCount && query.isEmpty {
                    Button(expanded.contains(id) ? "Show fewer" : "Show all \(matching.count)") {
                        withAnimation {
                            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("circle.showAll.\(id)")
                }
            } header: {
                SectionHeading(title: title, note: note)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    private func row(_ person: Profile, changes: [CircleChange]) -> some View {
        HStack(spacing: Spacing.m) {
            NavigationLink(value: ProfileRoute(userId: person.id, phoneHash: nil)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: person, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(DisplayNames.shared.contactsLabel(for: person.id)).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if changes == [.removeFollower] {
                followBackControl(person)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(changes, id: \.self) { change in
                if change == .unfollow {
                    Button("Unfollow", role: .destructive) { pending = (person, .unfollow) }
                } else {
                    Button("Remove") { pending = (person, .removeFollower) }
                        .tint(Palette.walnutDeep)
                }
            }
        }
    }

    /// Someone who follows you and you don't follow back: ask, or show Asked.
    @ViewBuilder
    private func followBackControl(_ person: Profile) -> some View {
        if let request = people.data.outgoing.first(where: { $0.targetId == person.id }) {
            Button("Asked") { pendingCancel = (request, person.displayName) }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHint("Waiting for their yes. Tap to take the request back.")
        } else {
            Button("Follow back") { Task { await people.sendFollowBack(to: person.id) } }
                .buttonStyle(.pill)
                .accessibilityLabel("Follow \(person.displayName) back")
        }
    }
}

extension View {
    /// Rows here draw their own chevrons (or a button) where they want one;
    /// stop the list adding a second to every row holding a link (iOS 26+).
    @ViewBuilder
    func hidesListLinkIndicators() -> some View {
        if #available(iOS 26.0, *) {
            navigationLinkIndicatorVisibility(.hidden)
        } else {
            self
        }
    }

    /// A list row that shows its content as-is on the page background: no
    /// cell background, separator or insets.
    func plainListRow(bottom: CGFloat = Spacing.l) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
