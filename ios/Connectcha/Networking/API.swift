import Foundation
import Supabase

/// The single Supabase client plus thin typed wrappers. Every call to the
/// server goes through here, which is also where the "nothing but hashes and
/// ids leave the device" rule is easiest to audit.
@MainActor
final class API {
    static let shared = API()

    let client: SupabaseClient

    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date \(raw)")
        }
        return d
    }()

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: .init(
                db: .init(encoder: API.encoder, decoder: API.decoder),
                auth: .init(flowType: .implicit),
                global: .init(session: URLSession(configuration: {
                    let c = URLSessionConfiguration.default
                    c.timeoutIntervalForRequest = 30
                    c.waitsForConnectivity = true
                    return c
                }()))
            )
        )
    }

    // MARK: RPC

    func rpc<T: Decodable & Sendable>(_ name: String, _ params: some Encodable & Sendable) async throws -> T {
        do {
            return try await client.rpc(name, params: params).execute().value
        } catch {
            throw APIError(error)
        }
    }

    func rpc<T: Decodable & Sendable>(_ name: String) async throws -> T {
        do {
            return try await client.rpc(name).execute().value
        } catch {
            throw APIError(error)
        }
    }

    func call(_ name: String, _ params: some Encodable & Sendable) async throws {
        do {
            _ = try await client.rpc(name, params: params).execute()
        } catch {
            throw APIError(error)
        }
    }

    func call(_ name: String) async throws {
        do {
            _ = try await client.rpc(name).execute()
        } catch {
            throw APIError(error)
        }
    }

    // MARK: Edge Functions

    func invoke<T: Decodable & Sendable>(_ name: String, body: some Encodable & Sendable) async throws -> T {
        do {
            let data: Data = try await client.functions.invoke(
                name,
                options: FunctionInvokeOptions(body: body)
            ) { @Sendable data, _ in data }
            return try API.decoder.decode(T.self, from: data)
        } catch {
            throw APIError(error)
        }
    }
}

/// Date strings as Postgres emits them in JSON (variable fractional digits,
/// "+00:00" offsets), parsed without surprises.
nonisolated enum DateParsing {
    // ISO8601DateFormatter is documented as thread-safe; the compiler can't know that.
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var s = raw
        if !s.contains("T") { s = s.replacingOccurrences(of: " ", with: "T") }
        if s.hasSuffix("+00") { s += ":00" }
        // Normalise fractional seconds to exactly three digits.
        if let dot = s.firstIndex(of: "."),
           let end = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let frac = s[s.index(after: dot)..<end]
            let three = String((frac + "000").prefix(3))
            s = String(s[..<dot]) + "." + three + String(s[end...])
            return fractional.date(from: s) ?? plain.date(from: s)
        }
        return plain.date(from: s) ?? fractional.date(from: s)
    }
}
