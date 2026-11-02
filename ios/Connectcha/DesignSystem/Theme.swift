import SwiftUI

// Warm, simple, uncluttered (spec 8.6). Colours come from the asset catalog so
// light and dark mode follow the phone. Type always uses system text styles so
// Dynamic Type works everywhere.

// Color.appBackground, .cardBackground and .subtleBackground are generated
// from the asset catalog by Xcode (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS).

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

/// Big, obvious, full-width primary action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, Spacing.m)
            .background(isEnabled ? Color.accentColor : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, Spacing.m)
            .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// Compact pill for inline actions (Request, Approve, Follow).
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(
                prominent ? (isEnabled ? Color.accentColor : Color.gray.opacity(0.35)) : Color.subtleBackground,
                in: Capsule()
            )
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var quietPill: PillButtonStyle { PillButtonStyle(prominent: false) }
}

/// Large single-line text field used in sign-in and onboarding.
struct BigFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 60)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension View {
    func bigField() -> some View { modifier(BigFieldModifier()) }
}

struct BrandMark: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Connectcha")
                .font(.largeTitle.bold())
        }
    }
}

/// Inline error shown under a form, readable at any text size.
struct ErrorText: View {
    let text: String?
    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.circle.fill")
                .font(.body)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(text)")
        }
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Side by side when the text fits, stacked when Dynamic Type is large.
struct AdaptiveStack<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = Spacing.s
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: alignment, spacing: spacing) { content() }
        } else {
            HStack(spacing: spacing) { content() }
        }
    }
}
