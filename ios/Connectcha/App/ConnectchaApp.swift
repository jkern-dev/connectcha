import SwiftUI
import UIKit

@main
struct ConnectchaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    /// True when this process hosts the unit test bundle (UI tests launch the
    /// app separately and don't see these variables). The real app must stay
    /// inert then: no session restore, no contact matching, no network.
    /// Otherwise its own startup traffic mixes into tests that record every
    /// request, such as the S7 "no names on the wire" check.
    nonisolated static let isHostingUnitTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }()

    init() {
        MediaCache.configureURLCache()
        if !Self.isHostingUnitTests { NotificationManager.shared.install() }
    }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingUnitTests {
                Text("Running unit tests")
                    .foregroundStyle(.secondary)
            } else {
                RootView()
                    .environment(model)
                    .task { model.start() }
            }
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
