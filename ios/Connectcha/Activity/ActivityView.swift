import SwiftUI

/// "Lately" (spec 10 in-app column): requests, approvals and lovelies, with
/// lovelies grouped per photo ("Mom and 3 others found your photo lovely"),
/// under day headings.
struct ActivityView: View {
    @Environment(AppModel.self) private var appModel
    @State private var items: [ActivityItem] = []
    @State private var people = PeopleModel()
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader(title: "Lately", subtitle: "What people in your circle did with your photos.")
                    .padding(.horizontal, Spacing.gutter)
                if loaded, items.isEmpty {
                    Text("When someone asks to see your photos, lets you in, or finds a photo lovely, it shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16)
                        .padding(.horizontal, Spacing.gutter)
                }
                ForEach(ActivityGrouping.days(ActivityGrouping.group(items))) { day in
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeading(title: day.label, rule: true)
                        ForEach(day.entries) { entry in
                            ActivityRowView(entry: entry, people: people)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
                if let error { ErrorText(text: error).padding(.horizontal, Spacing.gutter) }
                if loaded, !items.isEmpty {
                    Text("Nobody but you sees this list.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                        .padding(.horizontal, Spacing.gutter)
                }
            }
            .padding(.vertical, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .readablePage()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Lately")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .followBackPrompt(people: people)
        .onChange(of: people.data.incoming.count) { _, _ in Task { await load() } }
    }

    nonisolated struct LimitParams: Encodable, Sendable {
        let pLimit: Int
        enum CodingKeys: String, CodingKey { case pLimit = "p_limit" }
    }

    private func load() async {
        do {
            items = try await API.shared.rpc("get_activity", LimitParams(pLimit: 100))
            await people.load()
            await appModel.refreshUnread()
            error = nil
        } catch {
            self.error = APIError(error).message
        }
        loaded = true
    }
}

/// One row after grouping.
nonisolated struct ActivityEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable { case request(ActivityItem), approved(ActivityItem), likes(postId: UUID, actors: [Profile], cover: MediaItem?, latest: Date) }
    let id: String
    let kind: Kind
    let date: Date
}

/// Entries under one day heading.
nonisolated struct ActivityDay: Identifiable, Sendable {
    let label: String
    let entries: [ActivityEntry]
    var id: String { label }
}

nonisolated enum ActivityGrouping {
    static func group(_ items: [ActivityItem]) -> [ActivityEntry] {
        var out: [ActivityEntry] = []
        var likesByPost: [UUID: (actors: [Profile], cover: MediaItem?, latest: Date)] = [:]
        var likeOrder: [UUID] = []
        for item in items {
            switch item.type {
            case .followRequest:
                out.append(ActivityEntry(id: item.id.uuidString, kind: .request(item), date: item.createdAt))
            case .requestApproved:
                out.append(ActivityEntry(id: item.id.uuidString, kind: .approved(item), date: item.createdAt))
            case .like:
                guard let post = item.post else { continue }
                if var existing = likesByPost[post.id] {
                    if !existing.actors.contains(where: { $0.id == item.actor.id }) { existing.actors.append(item.actor) }
                    existing.latest = max(existing.latest, item.createdAt)
                    likesByPost[post.id] = existing
                } else {
                    likesByPost[post.id] = ([item.actor], post.cover, item.createdAt)
                    likeOrder.append(post.id)
                }
            }
        }
        for postId in likeOrder {
            if let g = likesByPost[postId] {
                out.append(ActivityEntry(id: "likes-\(postId)", kind: .likes(postId: postId, actors: g.actors, cover: g.cover, latest: g.latest), date: g.latest))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Sorted entries bucketed under "Today", "Yesterday", a weekday, a date.
    static func days(_ entries: [ActivityEntry], now: Date = Date()) -> [ActivityDay] {
        var out: [ActivityDay] = []
        for entry in entries {
            let label = FeedModel.dayLabel(for: entry.date, now: now)
            if let last = out.last, last.label == label {
                out[out.count - 1] = ActivityDay(label: label, entries: last.entries + [entry])
            } else {
                out.append(ActivityDay(label: label, entries: [entry]))
            }
        }
        return out
    }

    /// "Mom and 3 others"
    static func namesText(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Someone"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }
}

struct ActivityRowView: View {
    let entry: ActivityEntry
    let people: PeopleModel

    var body: some View {
        switch entry.kind {
        case .request(let item):
            if let request = people.data.incoming.first(where: { $0.id == item.requestId }) {
                RequestRow(request: request, people: people).card(padding: 16)
            } else {
                row(actor: item.actor, text: "\(item.actor.displayName) asked to see your photos.", date: item.createdAt, cover: nil, route: ProfileRoute(userId: item.actor.id, phoneHash: nil))
            }
        case .approved(let item):
            row(actor: item.actor, text: "\(item.actor.displayName) let you in.", link: "See their photos", date: item.createdAt, cover: nil, route: ProfileRoute(userId: item.actor.id, phoneHash: nil))
        case .likes(let postId, let actors, let cover, let latest):
            let names = actors.map(\.displayName)
            row(actor: actors[0], text: "\(ActivityGrouping.namesText(names)) found your photo lovely.", date: latest, cover: cover, route: PostRoute(postId: postId))
        }
    }

    private func row<Route: Hashable>(actor: Profile, text: String, link: String? = nil, date: Date, cover: MediaItem?, route: Route) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.m) {
                AvatarView(profile: actor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).font(.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    if let link { Text(link).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Text(RelativeTime.string(from: date)).font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                if let cover {
                    RemoteImage(mediaId: cover.id, variant: .thumb).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .card()
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .combine)
    }
}
