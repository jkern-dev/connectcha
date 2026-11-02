import Foundation
import Testing
@testable import Connectcha

/// Plan G1 / S7 for pushes: the server sends the profile name; the device swaps
/// in the saved contact name when it has one.
struct PushPayloadTests {
    let momId = UUID()

    var userInfo: [AnyHashable: Any] {
        [
            "type": "message",
            "actor_id": momId.uuidString,
            "actor_name": "Linda Kern",
            "conversation_id": UUID().uuidString,
            "kind": "post_response",
            "body_template": "{name} responded to your post",
        ]
    }

    @Test("payload parses and the saved name replaces the profile name")
    func rewrite() {
        let payload = PushPayload(userInfo: userInfo)
        #expect(payload?.kind == .message)
        #expect(payload?.actorId == momId)
        let body = PushPayload.rewrittenBody(template: payload?.bodyTemplate, originalBody: "Linda Kern responded to your post",
                                             actorId: momId, savedNames: { $0 == momId ? "Mom" : nil })
        #expect(body == "Mom responded to your post")
    }

    @Test("without a saved name the profile name stays")
    func fallback() {
        let body = PushPayload.rewrittenBody(template: "{name} wants to follow you", originalBody: "Sam Lee wants to follow you",
                                             actorId: UUID(), savedNames: { _ in nil })
        #expect(body == "Sam Lee wants to follow you")
        #expect(PushPayload.rewrittenBody(template: nil, originalBody: "x", actorId: momId, savedNames: { _ in "Mom" }) == "x")
    }

    @Test("unknown types are ignored")
    func unknown() {
        #expect(PushPayload(userInfo: ["type": "marketing"]) == nil)
    }

    @Test("the match map round-trips through the App Group file the extension reads")
    func matchMapForExtension() {
        let group = "group.test.push.\(UUID().uuidString)"
        MatchMap(ownerId: UUID(), entries: [momId: .init(contactIdentifier: "c", savedName: "Mom")], updatedAt: Date()).save(appGroup: group)
        let loaded = MatchMap.load(appGroup: group)
        #expect(PushPayload.rewrittenBody(template: "{name} approved your request", originalBody: "Linda Kern approved your request",
                                          actorId: momId, savedNames: { loaded?.savedName(for: $0) }) == "Mom approved your request")
        MatchMap.delete(appGroup: group)
    }
}
