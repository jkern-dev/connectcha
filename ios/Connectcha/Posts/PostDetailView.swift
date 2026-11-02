import SwiftUI

/// A single post: the card plus, for the poster, edit and delete.
struct PostDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let postId: UUID
    var feed: FeedModel?

    @State private var post: Post?
    @State private var error: String?
    @State private var showEdit = false
    @State private var showLikers = false
    @State private var confirmDelete = false
    @State private var showMenu = false

    var body: some View {
        ScrollView {
            if let post {
                PostCard(
                    post: post,
                    onLike: { Task { await toggleLike() } },
                    onOpenLikers: { showLikers = true },
                    onMessage: nil,
                    onMenu: post.isMine ? { showMenu = true } : nil
                )
                if post.isMine {
                    Text(post.responsesEnabled ? "Responses are on for this post." : "Responses are off for this post.")
                        .font(.subheadline).foregroundStyle(.secondary).padding()
                }
            } else if let error {
                VStack(spacing: Spacing.m) { ErrorText(text: error) }.padding()
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Post options", isPresented: $showMenu, titleVisibility: .hidden) {
            Button("Edit caption or location") { showEdit = true }
            Button("Delete post", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deletePost() } }
        } message: {
            Text("It disappears for everyone. Responses people sent will say \"Post no longer available\".")
        }
        .sheet(isPresented: $showEdit) {
            if let post { EditPostView(post: post) { updated in self.post = updated; feed?.replace(updated) } }
        }
        .sheet(isPresented: $showLikers) {
            if let post { LikersView(post: post) }
        }
        .appDestinations()
    }

    private func load() async {
        do {
            post = try await API.shared.rpc("get_post", FeedModel.PostParams(pPostId: postId))
        } catch {
            self.error = APIError(error).message
        }
    }

    private func toggleLike() async {
        guard var p = post else { return }
        let was = p.likedByMe
        p.likedByMe.toggle()
        p.likeCount += was ? -1 : 1
        post = p
        do {
            try await API.shared.call(was ? "unlike_post" : "like_post", FeedModel.PostParams(pPostId: p.id))
            feed?.replace(p)
        } catch {
            p.likedByMe = was
            p.likeCount += was ? 1 : -1
            post = p
            self.error = APIError(error).message
        }
    }

    private func deletePost() async {
        do {
            try await API.shared.call("delete_post", FeedModel.PostParams(pPostId: postId))
            feed?.remove(postId: postId)
            post?.media.forEach { MediaCache.shared.forget($0.id) }
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}

/// Spec 5.3: only the poster sees who liked.
struct LikersView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @State private var likers: [Profile] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if likers.isEmpty, error == nil {
                    Text("No likes yet.").foregroundStyle(.secondary)
                }
                ForEach(likers) { person in
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: person, size: 44)
                        Text(person.displayName).font(.body)
                    }
                    .padding(.vertical, Spacing.xs)
                }
                if let error { ErrorText(text: error) }
            }
            .navigationTitle("Liked by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do { likers = try await API.shared.rpc("get_post_likers", FeedModel.PostParams(pPostId: post.id)) }
                catch { self.error = APIError(error).message }
            }
        }
    }
}

/// Spec 5.2 and A4: caption and location can change after posting; media can't.
struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    var onSaved: (Post) -> Void

    @State private var caption: String
    @State private var location: PlaceChoice?
    @State private var responsesEnabled: Bool
    @State private var showLocation = false
    @State private var saving = false
    @State private var error: String?

    init(post: Post, onSaved: @escaping (Post) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _caption = State(initialValue: post.caption)
        _responsesEnabled = State(initialValue: post.responsesEnabled)
        if let name = post.locationName {
            _location = State(initialValue: PlaceChoice(name: name, latitude: post.locationLat, longitude: post.locationLng))
        }
    }

    nonisolated struct UpdateParams: Encodable, Sendable {
        let pPostId: UUID; let pCaption: String; let pLocationName: String?
        let pLocationLat: Double?; let pLocationLng: Double?; let pResponsesEnabled: Bool
        enum CodingKeys: String, CodingKey {
            case pPostId = "p_post_id", pCaption = "p_caption", pLocationName = "p_location_name"
            case pLocationLat = "p_location_lat", pLocationLng = "p_location_lng", pResponsesEnabled = "p_responses_enabled"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") {
                    TextField("Write a caption", text: $caption, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: caption) { _, new in if new.count > 1000 { caption = String(new.prefix(1000)) } }
                    Text("\(caption.count)/1000").font(.caption).foregroundStyle(.secondary)
                }
                Section("Location") {
                    Button {
                        showLocation = true
                    } label: {
                        HStack {
                            Label(location?.name ?? "Add a location", systemImage: "mappin.and.ellipse")
                            Spacer()
                            if location != nil {
                                Button("Remove", role: .destructive) { location = nil }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Allow responses", isOn: $responsesEnabled)
                } footer: {
                    Text("Responses are private messages to you, never public comments.")
                }
                if let error { Section { ErrorText(text: error) } }
            }
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving) }
            }
            .sheet(isPresented: $showLocation) { LocationSearchView(selection: $location) }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await API.shared.call("update_post", UpdateParams(
                pPostId: post.id, pCaption: caption, pLocationName: location?.name,
                pLocationLat: location?.latitude, pLocationLng: location?.longitude, pResponsesEnabled: responsesEnabled))
            var updated = post
            updated.caption = caption
            updated.locationName = location?.name
            updated.locationLat = location?.latitude
            updated.locationLng = location?.longitude
            updated.responsesEnabled = responsesEnabled
            onSaved(updated)
            dismiss()
        } catch {
            self.error = APIError(error).message
        }
    }
}
