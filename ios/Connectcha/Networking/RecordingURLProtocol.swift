#if DEBUG
import Foundation

/// Test hook: when active, intercepts every request the API client makes,
/// records it (URL, headers, body) and answers from a stub table instead of
/// the network. Inert unless `start` is called, so it costs nothing in normal
/// debug runs. Used by the "no contact names on the wire" test (S7).
nonisolated final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated struct Recorded: Sendable {
        let url: String
        let headers: [String: String]
        let body: String

        /// Everything about the request, flattened, for substring checks.
        var everything: String {
            url + "\n" + headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n") + "\n" + body
        }
    }

    nonisolated struct Stub: Sendable {
        let pathContains: String
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _active = false
    nonisolated(unsafe) private static var _stubs: [Stub] = []
    nonisolated(unsafe) private static var _recorded: [Recorded] = []

    static var isActive: Bool { lock.withLock { _active } }
    static var recorded: [Recorded] { lock.withLock { _recorded } }

    static func start(stubs: [Stub]) {
        lock.withLock {
            _active = true
            _stubs = stubs
            _recorded = []
        }
    }

    static func stop() {
        lock.withLock {
            _active = false
            _stubs = []
        }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { isActive }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readStream(request.httpBodyStream) ?? Data()
        let record = Recorded(
            url: request.url?.absoluteString ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: String(decoding: body, as: UTF8.self)
        )
        let stub = Self.lock.withLock { () -> Stub? in
            Self._recorded.append(record)
            return Self._stubs.first { record.url.contains($0.pathContains) }
        }
        let status = stub?.status ?? 404
        let data = stub?.body ?? Data("{\"error\":\"no_stub\"}".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: bufferSize)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
#endif
