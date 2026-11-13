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
    @State private var composing = false

    var body: some View {
        ScrollView {
            if let post {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    PostCard(
                        post: post,
                        onLike: { Task { await toggleLike() } },
                        onOpenLikers: { showLikers = true },
                        onMessage: post.isMine ? nil : { composing = true },
                        onMenu: post.isMine ? { showMenu = true } : nil
                    )
                    if post.isMine {
                        Text(post.responsesEnabled ? "People can write back to this photo." : "Write-backs are off for this photo.")
                            .font(.footnote).foregroundStyle(Palette.muted).padding(.horizontal, 4)
                    }
                }
                .padding(Spacing.gutter)
            } else if let error {
                VStack(spacing: Spacing.m) { ErrorText(text: error) }.padding()
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .readablePage()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(post.map { FeedModel.dayLabel(for: $0.publishedAt ?? Date()) } ?? "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Photo options", isPresented: $showMenu, titleVisibility: .hidden) {
            Button("Change the words or the place") { showEdit = true }
            Button("Take it off the table", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Take this off the table?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deletePost() } }
        } message: {
            Text("It disappears for everyone. Letters people wrote about it will say the photo is no longer on the table.")
        }
        .sheet(isPresented: $showEdit) {
            if let post { EditPostView(post: post) { updated in self.post = updated; feed?.replace(updated) } }
        }
        .sheet(isPresented: $showLikers) {
            if let post { LikersView(post: post) }
        }
        .sheet(isPresented: $composing) {
            NavigationStack { ComposeResponseView(postId: postId, onSent: {}) }
                .presentationDetents([.medium, .large])
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
                    Text("Nobody yet.").foregroundStyle(Palette.muted)
                }
                ForEach(likers) { person in
                    HStack(spacing: Spacing.m) {
                        AvatarView(profile: person, size: 44)
                        Text(person.displayName).font(.body).foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, Spacing.xs)
                }
                if let error { ErrorText(text: error) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Found it lovely")
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

        /// As for `CreatePostView.CreateParams`: an empty place goes as null.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pPostId, forKey: .pPostId)
            try c.encode(pCaption, forKey: .pCaption)
            try c.encode(pLocationName, forKey: .pLocationName)
            try c.encode(pLocationLat, forKey: .pLocationLat)
            try c.encode(pLocationLng, forKey: .pLocationLng)
            try c.encode(pResponsesEnabled, forKey: .pResponsesEnabled)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("On the back") {
                    TextField("A few words, if you like", text: $caption, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.serif(.body)).italic()
                        .onChange(of: caption) { _, new in if new.count > 1000 { caption = String(new.prefix(1000)) } }
                    Text("\(caption.count)/1000").font(.caption).foregroundStyle(Palette.muted)
                }
                Section("Where") {
                    Button {
                        showLocation = true
                    } label: {
                        HStack {
                            Label(location?.name ?? "Add a place", systemImage: "mappin.and.ellipse")
                            Spacer()
                            if location != nil {
                                Button("Remove", role: .destructive) { location = nil }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Let people write back", isOn: $responsesEnabled).tint(Color.accentColor)
                } footer: {
                    Text("Write-backs come to you as letters, never as public comments.")
                }
                if let error { Section { ErrorText(text: error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .keyboardCanBePutAway()
            .navigationTitle("Change the words")
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
