import Foundation
import Supabase
import UserNotifications

/// Debug/simulator only. When CONNECTCHA_INAPP_PUSH=1 (UI tests), polls the
/// stubbed deliveries addressed to this simulator's token and presents them as
/// local notifications, applying the same saved-name rewrite the extension
/// would. The demo uses scripts/push-bridge.sh instead, which goes through
/// `simctl push` and the real Notification Service Extension.
@MainActor
final class DebugPushPoller {
    static let shared = DebugPushPoller()
    private var task: Task<Void, Never>?

    nonisolated struct Delivery: Decodable, Sendable {
        let id: Int
        let payload: [String: AnyCodableValue]
    }
    nonisolated struct AckParams: Encodable, Sendable {
        let pIds: [Int]
        enum CodingKeys: String, CodingKey { case pIds = "p_ids" }
    }

    func startIfEnabled() async {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["CONNECTCHA_INAPP_PUSH"] == "1", task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.poll()
            }
        }
        #endif
    }

    private func poll() async {
        guard API.shared.client.auth.currentSession != nil else { return }
        guard let deliveries: [Delivery] = try? await API.shared.rpc("my_pending_pushes"), !deliveries.isEmpty else { return }
        let map = MatchMap.load(appGroup: AppConfig.appGroupIdentifier)
        for d in deliveries {
            let userInfo = d.payload.mapValues { $0.value }
            let aps = userInfo["aps"] as? [String: Any]
            let alert = aps?["alert"] as? [String: Any]
            let content = UNMutableNotificationContent()
            content.title = alert?["title"] as? String ?? "Connectcha"
            let body = alert?["body"] as? String ?? ""
            let payload = PushPayload(userInfo: userInfo)
            content.body = PushPayload.rewrittenBody(template: payload?.bodyTemplate, originalBody: body,
                                                     actorId: payload?.actorId, savedNames: { map?.savedName(for: $0) })
            content.sound = .default
            content.userInfo = userInfo.filter { $0.key != "aps" }
            let request = UNNotificationRequest(identifier: "debug-push-\(d.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
        try? await API.shared.call("ack_pushes", AckParams(pIds: deliveries.map(\.id)))
    }
}

/// Minimal JSON value wrapper for the push payload dictionary.
nonisolated enum AnyCodableValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), null, object([String: AnyCodableValue]), array([AnyCodableValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let o = try? c.decode([String: AnyCodableValue].self) { self = .object(o) }
        else if let a = try? c.decode([AnyCodableValue].self) { self = .array(a) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON") }
    }

    var value: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) : n
        case .bool(let b): return b
        case .null: return NSNull()
        case .object(let o): return o.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        }
    }
}
