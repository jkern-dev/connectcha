import SwiftUI

@main
struct ConnectchaApp: App {
    @State private var model = AppModel()

    init() {
        MediaCache.configureURLCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.start() }
        }
    }
}
