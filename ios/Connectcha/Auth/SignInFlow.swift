import SwiftUI
import Supabase

/// Spec 9.1 step 1 and 9.4: phone number, then the texted code.
struct SignInFlow: View {
    @State private var path: [Step] = []
    @State private var phoneDigits = ""

    enum Step: Hashable { case code(e164: String) }

    var body: some View {
        NavigationStack(path: $path) {
            PhoneEntryView(digits: $phoneDigits) { e164 in
                path.append(.code(e164: e164))
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .code(let e164):
                    CodeEntryView(e164: e164)
                }
            }
        }
    }
}

struct PhoneEntryView: View {
    @Binding var digits: String
    var onCodeSent: (String) -> Void

    @State private var error: String?
    @State private var isSending = false
    @FocusState private var focused: Bool

    private var normalized: PhoneNormalizer.Result { PhoneNormalizer.normalize(digits) }
    private var canContinue: Bool {
        if case .us = normalized { return !isSending }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                BrandMark()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xl)

                ScreenHeader(
                    title: "Your phone number",
                    subtitle: "We'll text you a code to sign in. Connectcha works with US numbers."
                )

                HStack(spacing: Spacing.s) {
                    Text("+1")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Country code plus one, United States")
                    TextField("(555) 000-0001", text: Binding(
                        get: { PhoneNormalizer.formatUSForDisplay(digits: digits) },
                        set: { digits = String($0.filter(\.isNumber).prefix(11)) }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focused)
                    .accessibilityLabel("Phone number")
                    .submitLabel(.continue)
                }
                .bigField()

                if digits.count >= 10, case .invalid = normalized {
                    ErrorText(text: "That doesn't look like a US phone number.")
                }
                ErrorText(text: error)

                Button {
                    Task { await sendCode() }
                } label: {
                    if isSending { ProgressView().tint(.white) } else { Text("Text me a code") }
                }
                .buttonStyle(.primary)
                .disabled(!canContinue)
                .accessibilityHint("Sends a text message with a sign-in code")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("By continuing you agree to the")
                    HStack(spacing: Spacing.xs) {
                        Link("Terms", destination: AppConfig.termsURL)
                        Text("and")
                        Link("Privacy Policy", destination: AppConfig.privacyURL)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func sendCode() async {
        guard case .us(let e164) = normalized else {
            error = "Only US phone numbers can sign up right now."
            return
        }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            try await API.shared.client.auth.signInWithOTP(phone: e164)
            onCodeSent(e164)
        } catch {
            self.error = APIError(error).message
        }
    }
}

struct CodeEntryView: View {
    let e164: String

    @State private var code = ""
    @State private var error: String?
    @State private var isVerifying = false
    @State private var resent = false
    @FocusState private var focused: Bool

    private var displayNumber: String {
        PhoneNormalizer.formatUSForDisplay(digits: String(e164.dropFirst(2)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader(
                    title: "Enter your code",
                    subtitle: "We texted a 6-digit code to \(displayNumber)."
                )
                .padding(.top, Spacing.l)

                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .bigField()
                    .accessibilityLabel("Six digit code")
                    .onChange(of: code) { _, new in
                        let cleaned = String(new.filter(\.isNumber).prefix(6))
                        if cleaned != new { code = cleaned }
                        if cleaned.count == 6 { Task { await verify() } }
                    }

                ErrorText(text: error)

                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying { ProgressView().tint(.white) } else { Text("Sign in") }
                }
                .buttonStyle(.primary)
                .disabled(code.count != 6 || isVerifying)

                Button(resent ? "Code sent again" : "Send a new code") {
                    Task { await resend() }
                }
                .buttonStyle(.secondary)
                .disabled(resent)
            }
            .padding(Spacing.l)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func verify() async {
        guard !isVerifying, code.count == 6 else { return }
        isVerifying = true
        error = nil
        defer { isVerifying = false }
        do {
            try await API.shared.client.auth.verifyOTP(phone: e164, token: code, type: .sms)
            // AppModel observes the auth change and moves on.
        } catch {
            self.error = APIError(error).message
            code = ""
        }
    }

    private func resend() async {
        do {
            try await API.shared.client.auth.signInWithOTP(phone: e164)
            resent = true
        } catch {
            self.error = APIError(error).message
        }
    }
}
