import Foundation

/// Build-time configuration from Info.plist (filled from Config/Local.xcconfig).
enum AppConfig {
    private static let info = Bundle.main.infoDictionary ?? [:]

    static let supabaseURL: URL = {
        let raw = (info["SupabaseURL"] as? String) ?? "http://127.0.0.1:54321"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:54321")!
    }()

    static let supabaseAnonKey: String = (info["SupabaseAnonKey"] as? String) ?? ""

    static let inviteURL: URL = {
        let raw = (info["InviteURL"] as? String) ?? "http://127.0.0.1:8787/"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:8787/")!
    }()

    static let supportEmail: String = (info["SupportEmail"] as? String) ?? "ask.connectcha@gmail.com"

    static let appGroupIdentifier: String = (info["AppGroupIdentifier"] as? String) ?? "group.com.connectcha.shared"

    static let privacyURL: URL = inviteURL.appendingPathComponent("privacy.html")
    static let termsURL: URL = inviteURL.appendingPathComponent("terms.html")

    /// Demo mode (simulator walkthroughs): seeds the persona's contacts and
    /// registers a simulator push token. Only ever true in DEBUG builds.
    static var isDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["CONNECTCHA_DEMO"] == "1"
        #else
        return false
        #endif
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
