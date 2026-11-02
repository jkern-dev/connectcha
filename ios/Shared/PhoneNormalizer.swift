import Foundation

/// Turns whatever is typed or saved in a contact into an E.164 number.
///
/// Rules (spec 2, 4.2): numbers without a country code are US numbers; only
/// US numbers can sign up; non-US contacts are kept in the invite list but get
/// a "country code not accepted" message. Shared by the app and the
/// Notification Service Extension so both hash the same way.
nonisolated enum PhoneNormalizer {
    enum Result: Equatable, Sendable {
        /// A valid US number, as +1XXXXXXXXXX.
        case us(e164: String)
        /// A plausibly complete number from another country, as +<digits>.
        case nonUS(e164: String)
        /// Not a usable number (too short, an extension, a shortcode, etc.).
        case invalid
    }

    static func normalize(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        // Keep digits; remember whether an explicit "+" led the number.
        // Anything after an extension marker is dropped.
        let withoutExtension = trimmed
            .components(separatedBy: CharacterSet(charactersIn: "xX;,")).first ?? trimmed
        let hasPlus = withoutExtension.hasPrefix("+")
        var digits = withoutExtension.filter(\.isNumber)
        // Fold non-ASCII digits (some contacts arrive with full-width digits).
        digits = String(digits.compactMap { $0.wholeNumberValue }.map { Character(String($0)) })

        if hasPlus {
            return classifyInternational(digits)
        }
        // "011" is the North American prefix for dialling abroad.
        if digits.hasPrefix("011"), digits.count > 11 {
            return classifyInternational(String(digits.dropFirst(3)))
        }
        if digits.count == 10 {
            return usIfValid(areaAndNumber: digits)
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return usIfValid(areaAndNumber: String(digits.dropFirst()))
        }
        return .invalid
    }

    private static func classifyInternational(_ digits: String) -> Result {
        if digits.hasPrefix("1"), digits.count == 11 {
            return usIfValid(areaAndNumber: String(digits.dropFirst()))
        }
        // Shortest real international numbers are around 8 digits; longest 15.
        if digits.count >= 8, digits.count <= 15, !digits.hasPrefix("1") {
            return .nonUS(e164: "+" + digits)
        }
        return .invalid
    }

    private static func usIfValid(areaAndNumber: String) -> Result {
        // Area codes never start with 0 or 1. Exchanges technically can't either,
        // but test and fictional numbers (555-000-xxxx) do, and the server has
        // the final say, so only the area code is checked here.
        guard areaAndNumber.count == 10,
              let first = areaAndNumber.first, first != "0", first != "1"
        else { return .invalid }
        return .us(e164: "+1" + areaAndNumber)
    }

    /// "(555) 000-0001" for display; never shown for other people, only for
    /// the user's own number while signing in.
    static func formatUSForDisplay(digits: String) -> String {
        let d = digits.filter(\.isNumber).prefix(10)
        var out = ""
        for (i, ch) in d.enumerated() {
            switch i {
            case 0: out += "("
            case 3: out += ") "
            case 6: out += "-"
            default: break
            }
            out.append(ch)
        }
        return out
    }
}
