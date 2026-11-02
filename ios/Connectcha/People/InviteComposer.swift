import MessageUI
import SwiftUI
import UIKit

/// Spec 4.3: "Invite" opens the phone's own Messages app with a pre-written
/// text and the invite link; the user sends it. On a simulator, where Messages
/// isn't available, a share sheet carries the same text.
enum Invite {
    static var text: String {
        "I'm on Connectcha, a private photo app just for friends and family. Join me: \(AppConfig.inviteURL.absoluteString)"
    }

    static var canUseMessages: Bool { MFMessageComposeViewController.canSendText() }
}

struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Presents the right thing for an invite tap: Messages, a share sheet, or
/// the non-US message (spec 4.3, S9).
struct InviteAction: ViewModifier {
    @Binding var candidate: InviteCandidate?
    @State private var showNonUS = false
    @State private var composing: InviteCandidate?
    @State private var sharing: InviteCandidate?

    func body(content: Content) -> some View {
        content
            .onChange(of: candidate) { _, new in
                guard let new else { return }
                candidate = nil
                if !new.isUS {
                    showNonUS = true
                } else if Invite.canUseMessages {
                    composing = new
                } else {
                    sharing = new
                }
            }
            .alert("Not available yet", isPresented: $showNonUS) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Connectcha only works with US phone numbers right now, so this person's country code isn't accepted yet.")
            }
            .sheet(item: $composing) { c in
                MessageComposer(recipient: c.usNumber ?? "", body: Invite.text) { composing = nil }
                    .ignoresSafeArea()
            }
            .sheet(item: $sharing) { _ in
                ShareSheet(items: [Invite.text])
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    func inviteAction(_ candidate: Binding<InviteCandidate?>) -> some View {
        modifier(InviteAction(candidate: candidate))
    }
}
