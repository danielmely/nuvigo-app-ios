import Foundation
import Combine

/// Small helpers shared by the service clients.
nonisolated enum HTTP {
    static func send(_ url: URL, method: String = "GET", headers: [String: String] = [:],
                     body: Data? = nil, timeout: TimeInterval = 20) async throws -> (Int, Data) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private static let unreserved = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /// Appends strictly percent-encoded query items to `string`.
    static func url(_ string: String, query: [String: String] = [:]) -> URL? {
        let q = query.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
        if q.isEmpty { return URL(string: string) }
        return URL(string: string + (string.contains("?") ? "&" : "?") + q)
    }

    static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func array(_ data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    static func json(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    static func form(_ pairs: [String: String]) -> Data {
        Data(pairs.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&").utf8)
    }

    static func multipart(_ fields: [String: String], boundary: String) -> Data {
        var body = Data()
        for (k, v) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
