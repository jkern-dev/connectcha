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

/// Three prints on the table, the wordmark, the one-line promise, and one
/// field.
struct PhoneEntryView: View {
    @Binding var digits: String
    var onCodeSent: (String) -> Void

    @State private var error: String?
    @State private var isSending = false
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var normalized: PhoneNormalizer.Result { PhoneNormalizer.normalize(digits) }
    private var canContinue: Bool {
        if case .us = normalized { return !isSending }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if !typeSize.isAccessibilitySize {
                    WelcomePrints()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.l)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connectcha")
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Photos for the people in your phone, and nobody else.")
                        .font(.serif(.title3)).italic()
                        .foregroundStyle(Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, typeSize.isAccessibilitySize ? Spacing.xl : 0)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your mobile number").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: Spacing.s) {
                        Text("US +1")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1.5))
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
                        .bigField()
                    }
                    Text("We text you a six-digit code. US numbers only for now. Your number is how friends find you; it is never shown to anyone.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if digits.count >= 10, case .invalid = normalized {
                    ErrorText(text: "That doesn't look like a US phone number.")
                }
                ErrorText(text: error)

                Button {
                    Task { await sendCode() }
                } label: {
                    if isSending { ProgressView().tint(.white) } else { Text("Text me the code") }
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
                    Text("Nothing here is public, ever.")
                }
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
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

/// Decorative prints for the first screen: no real photos, just three tinted
/// cards with a word each.
struct WelcomePrints: View {
    private let prints: [(Color, String, String)] = [
        (Color(red: 0.616, green: 0.706, blue: 0.627), "leaf", "the garden"),
        (Color(red: 0.722, green: 0.769, blue: 0.839), "water.waves", "the coast"),
        (Color(red: 0.847, green: 0.706, blue: 0.627), "bicycle", "the bike"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: -6) {
            ForEach(Array(prints.enumerated()), id: \.offset) { index, print in
                PrintFrame(tilt: [-7, 4, -2][index], width: 108, height: 136, label: print.2) {
                    ZStack {
                        print.0
                        Image(systemName: print.1).font(.title).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .offset(y: [0, 24, -4][index])
            }
        }
        .frame(height: 170)
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
                    title: "Type the code",
                    subtitle: "We texted six digits to \(displayNumber)."
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
