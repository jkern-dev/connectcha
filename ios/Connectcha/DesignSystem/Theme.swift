import SwiftUI
import UIKit

// The kitchen table (DESIGN_DIRECTION.md): warm paper, a serif for headings and
// captions, photos as prints with a white border, pills for buttons, plain
// sentences instead of icons. Colours come from the asset catalog where Xcode
// generates symbols (Color.appBackground, .cardBackground, .subtleBackground,
// .accentColor) and from `Palette` for the rest; both follow light and dark
// mode and stay warm in the dark. Type always uses system text styles so
// Dynamic Type works everywhere.

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    /// Side gutter used by every screen.
    static let gutter: CGFloat = 20
}

enum Radius {
    static let card: CGFloat = 18
    static let media: CGFloat = 12
    static let print: CGFloat = 6
}

/// Named colours beyond the four in the asset catalog. Nonisolated because
/// SwiftUI resolves dynamic colours on its render thread, not the main actor.
nonisolated enum Palette {
    /// Primary text.
    static let ink = dynamic(light: 0x2B211A, dark: 0xF3EBE0)
    /// Captions and longer text.
    static let body = dynamic(light: 0x3B2F27, dark: 0xE0D5C8)
    /// Secondary text; dark enough for small sizes on paper.
    static let muted = dynamic(light: 0x6B5B4F, dark: 0xB8A898)
    /// The accent, pressed.
    static let walnutDeep = dynamic(light: 0x5E3A24, dark: 0xE0A47C)
    /// Your own message bubbles, segmented backgrounds.
    static let tint = dynamic(light: 0xE9DCCB, dark: 0x3D312A)
    /// Dividers on paper.
    static let hairline = dynamic(light: 0xE2D7C8, dark: 0x3A312B)
    /// Dividers inside a card.
    static let hairlineInCard = dynamic(light: 0xF0E8DC, dark: 0x3A312B)
    /// Secondary button borders.
    static let border = dynamic(light: 0xD9CBB9, dark: 0x4A3E36)
    /// Inactive tab items.
    static let inactive = dynamic(light: 0x5B4A3F, dark: 0xB8A898)
    /// Dashed outlines ("Add yours").
    static let dashed = dynamic(light: 0xB9A896, dark: 0x6A5B50)
    /// Shadow colour for cards and prints.
    static let shadow = Color(red: 43 / 255, green: 33 / 255, blue: 26 / 255)
    /// A print's border stays paper-white in both modes, like a real print.
    static let printPaper = dynamic(light: 0xFFFFFF, dark: 0xF3EBE0)
    /// Writing on a print is always dark on that white.
    static let printInk = dynamic(light: 0x2B211A, dark: 0x2B211A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

nonisolated extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// Headings, day labels and the wordmark: the system serif (New York),
    /// which scales with Dynamic Type like every other text style.
    static func serif(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

extension View {
    /// Italic serif for captions and "a line on the back".
    func captionSerif(_ style: Font.TextStyle = .body) -> some View {
        font(.serif(style)).italic().foregroundStyle(Palette.body)
    }

    /// A white card on the paper background.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Palette.shadow.opacity(0.10), radius: 2, y: 1)
    }

    /// The soft, bordered box used for notes and quiet rows.
    func softBox() -> some View {
        self
            .padding(14)
            .background(Color.subtleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline))
    }

    /// Hides the system bar on a tab root so the screen can draw its own
    /// header; pushed screens get the bar back.
    ///
    /// With `sideStrip` (iPhone Duo) the bar stays, without its title,
    /// because the system draws its buttons in the strip beside the page.
    func kitchenTableRoot(title: String, sideStrip: Bool = false) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: sideStrip ? .title : nil)
            .toolbar(sideStrip ? .automatic : .hidden, for: .navigationBar)
            .toolbarBackground(Color.appBackground, for: .tabBar)
    }
}

// MARK: - Buttons

/// Big, obvious, full-width primary action: a walnut pill.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Spacing.m)
            .background(isEnabled ? (configuration.isPressed ? Palette.walnutDeep : Color.accentColor) : Palette.border, in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
    }
}

/// Full-width secondary action: soft fill with a hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Spacing.m)
            .background(Color.subtleBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1.5))
            .foregroundStyle(Palette.ink)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Compact pill for inline actions ("Ask to follow", "Yes, let Dad in").
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(prominent ? .bold : .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                prominent ? (isEnabled ? (configuration.isPressed ? Palette.walnutDeep : Color.accentColor) : Palette.border) : Color.subtleBackground,
                in: Capsule()
            )
            .overlay {
                if !prominent { Capsule().strokeBorder(Palette.border, lineWidth: 1.5) }
            }
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .opacity(!prominent && configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A plain link-looking action ("Write back to Ana").
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? Palette.walnutDeep : Color.accentColor)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { LinkButtonStyle() }
}

// MARK: - Fields

/// Large single-line text field used in sign-in and onboarding.
struct BigFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 56)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1.5))
    }
}

extension View {
    func bigField() -> some View { modifier(BigFieldModifier()) }
}

// MARK: - Pieces

/// The wordmark in the serif.
struct BrandMark: View {
    var size: Font.TextStyle = .largeTitle
    var body: some View {
        Text("Connectcha")
            .font(.serif(size, weight: .bold))
            .foregroundStyle(Palette.ink)
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

/// Large serif title with an optional plain sentence under it.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Today ———" or "People you know   from your contacts": a serif heading with
/// either a rule or a quiet note on the right.
struct SectionHeading: View {
    let title: String
    var note: String? = nil
    var rule = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // The note goes under the title instead of fighting it for width.
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let note { noteText(note) }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    titleText
                    if rule {
                        Rectangle().fill(Palette.hairline).frame(height: 1).frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                    if let note { noteText(note) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleText: some View {
        Text(title)
            .font(.serif(.title3, weight: .medium))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func noteText(_ note: String) -> some View {
        Text(note).font(.footnote).foregroundStyle(Palette.muted)
    }
}

/// A photo print: white border, small radius, a slight tilt. The tilt is
/// decorative and is dropped at accessibility text sizes, where prints become
/// plain rows.
struct PrintFrame<Content: View>: View {
    var tilt: Double = 0
    var width: CGFloat = 96
    var height: CGFloat = 124
    var label: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 6) {
            content()
                .frame(width: width - 12, height: height - (label == nil ? 12 : 36))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            if let label {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.printInk)
                    .lineLimit(1)
                    .padding(.bottom, 2)
            }
        }
        .padding(6)
        .frame(width: width, height: height)
        .background(Palette.printPaper, in: RoundedRectangle(cornerRadius: Radius.print, style: .continuous))
        .shadow(color: Palette.shadow.opacity(0.15), radius: 3, y: 2)
        .rotationEffect(.degrees(tilt))
    }
}

/// Tilts that read as "put down by hand", cycling by position.
enum Tilt {
    static let cycle: [Double] = [-3, 2, -1, 3, -2, 1]
    static func at(_ index: Int) -> Double { cycle[index % cycle.count] }
}

/// A hairline row divider inside a card.
struct CardDivider: View {
    var body: some View { Rectangle().fill(Palette.hairlineInCard).frame(height: 1) }
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

/// Pressing a whole card: no highlight colour, a slight dim.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
extension ButtonStyle where Self == CardPressStyle {
    static var cardPress: CardPressStyle { CardPressStyle() }
}

/// Today's date the way the Home header shows it: "Sunday 2 November".
nonisolated enum DateWords {
    static func long(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: date)
    }
}

// MARK: - Wide windows (iPhone Duo unfolded)

/// Two pages side by side, like an open album. Each page takes exactly half
/// the width, so on a folding screen the join between them sits on the fold
/// and no control straddles it.
struct TwoPages<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        GeometryReader { proxy in
            let fold = Self.fold(in: proxy)
            HStack(spacing: 0) {
                left().frame(width: fold.minX, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                Color.clear.frame(width: fold.width)
                right().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// Where the pages meet, in this view's own coordinates: on the device's
    /// fold when the system reports one inside the view (iOS 27.1 and later),
    /// otherwise the middle. The two differ on an iPhone Duo because the
    /// strip of system buttons takes room on one edge only. While the device
    /// is partly open the fold is "active" and nothing should sit on it, so
    /// the pages keep clear of its whole width; opened flat they simply meet
    /// on its centre line.
    private static func fold(in proxy: GeometryProxy) -> (minX: CGFloat, width: CGFloat) {
        let size = proxy.size
        if #available(iOS 27.1, *) {
            let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
            if let fold = folds.first(where: { $0.frame.height >= size.height / 2
                                               && $0.frame.minX > size.width * 0.25
                                               && $0.frame.maxX < size.width * 0.75 }) {
                return fold.isActive ? (fold.frame.minX, fold.frame.width) : (fold.frame.midX, 0)
            }
        }
        return (size.width / 2, 0)
    }
}

/// Whether a screen should lay itself out as two pages. Driven by the size
/// class only (never the device or the pose), and off at accessibility text
/// sizes, where half a window is too narrow to read comfortably.
struct WideLayout: DynamicProperty {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var isOn: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }
}

extension View {
    /// Keeps a single-column screen at a comfortable reading width, centred,
    /// when the window is much wider than a phone.
    func readablePage(maxWidth: CGFloat = 620) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// Publishes `\.sideStrip` to everything inside. Apply once, around the
    /// tab view: read there the system's answer holds steady through a fold,
    /// while inside a navigation stack it flickers and can settle wrong.
    func readsSideStrip() -> some View {
        modifier(SideStripProbe())
    }

    /// For screens with a multi-line text field, where Return adds a line and
    /// so cannot put the keyboard away: dragging the page down dismisses it,
    /// and a Done button sits above the keys.
    func keyboardCanBePutAway() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Hide keyboard")
                }
            }
    }

    /// A sheet on a phone-width window; the whole window when it is wide, so
    /// the content keeps its two pages instead of shrinking into a form sheet.
    func sheetOrCover<Content: View>(isPresented: Binding<Bool>, wide: Bool,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        self
            .sheet(isPresented: wide ? .constant(false) : isPresented, content: content)
            .fullScreenCover(isPresented: wide ? isPresented : .constant(false), content: content)
    }
}

extension EnvironmentValues {
    /// True while the system draws toolbar items in a strip down one side of
    /// the window instead of a bar across the top (iPhone Duo, folded or
    /// open, iOS 27.1 and later). Always false on earlier systems.
    @Entry var sideStrip = false
}

private struct SideStripProbe: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(Reader())
        } else {
            content
        }
    }

    @available(iOS 27.1, *)
    private struct Reader: ViewModifier {
        @Environment(\.toolbarVerticalEdge) private var edge

        func body(content: Content) -> some View {
            content.environment(\.sideStrip, edge != nil)
        }
    }
}
