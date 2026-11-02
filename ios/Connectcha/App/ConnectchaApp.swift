import SwiftUI
import UIKit

@main
struct ConnectchaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        MediaCache.configureURLCache()
        NotificationManager.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.start() }
        }
    }
}

/// APNs registration callbacks (real devices) land here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token: pushes stay off for this device. Nothing else to do.
    }
}
