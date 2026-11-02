import SwiftUI

/// Spec 10 in-app column: follow requests, approvals and likes, with likes
/// grouped per post ("Mom and 3 others liked your post").
struct ActivityView: View {
    @Environment(AppModel.self) private var appModel
    @State private var items: [ActivityItem] = []
    @State private var people = PeopleModel()
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        List {
            if loaded, items.isEmpty {
                Text("When someone requests to follow you, approves you or likes a post, it shows up here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(ActivityGrouping.group(items)) { entry in
                ActivityRowView(entry: entry, people: people)
            }
            if let error { ErrorText(text: error) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Activity")
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
                RequestRow(request: request, people: people)
            } else {
                row(actor: item.actor, text: "\(item.actor.displayName) requested to follow you", date: item.createdAt, cover: nil, route: ProfileRoute(userId: item.actor.id, phoneHash: nil))
            }
        case .approved(let item):
            row(actor: item.actor, text: "\(item.actor.displayName) approved your request", date: item.createdAt, cover: nil, route: ProfileRoute(userId: item.actor.id, phoneHash: nil))
        case .likes(let postId, let actors, let cover, let latest):
            let names = actors.map(\.displayName)
            NavigationLink(value: PostRoute(postId: postId)) {
                HStack(spacing: Spacing.m) {
                    AvatarView(profile: actors[0], size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ActivityGrouping.namesText(names)) liked your post").font(.body)
                        Text(RelativeTime.string(from: latest)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cover {
                        RemoteImage(mediaId: cover.id, variant: .thumb).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func row(actor: Profile, text: String, date: Date, cover: MediaItem?, route: ProfileRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.m) {
                AvatarView(profile: actor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).font(.body)
                    Text(RelativeTime.string(from: date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}
