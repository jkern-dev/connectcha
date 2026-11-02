import CryptoKit
import Foundation

/// SHA-256 of the E.164 number, hex encoded: the only form of a phone number
/// that ever leaves the device, and only for matching (plan 3.2, R-E).
nonisolated enum PhoneHasher {
    static func hash(e164: String) -> String {
        let digest = SHA256.hash(data: Data(e164.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
