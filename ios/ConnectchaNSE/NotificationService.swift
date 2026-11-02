import UserNotifications

/// Rewrites the sender's name in an incoming push using the match map the app
/// keeps in the App Group container (plan G1). The server only ever knows
/// profile names; the saved contact name is substituted here, on the device.
/// If anything is missing the original text is shown unchanged.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    static let appGroup = "group.com.connectcha.shared"

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content

        if let payload = PushPayload(userInfo: content.userInfo),
           let map = MatchMap.load(appGroup: Self.appGroup) {
            content.body = PushPayload.rewrittenBody(
                template: payload.bodyTemplate,
                originalBody: content.body,
                actorId: payload.actorId,
                savedNames: { map.savedName(for: $0) }
            )
        }
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt {
            contentHandler(bestAttempt)
        }
    }
}
