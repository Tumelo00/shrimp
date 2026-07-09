import Foundation

enum AgentError: Error, LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Geçersiz sunucu adresi"
        case .http(let code): return code == 401 ? "Token hatalı (401)" : "Sunucu hatası (HTTP \(code))"
        }
    }
}

struct AgentAPI: Sendable {
    var host: String
    var port: Int
    var token: String

    private func url(scheme: String, path: String, query: [String: String]) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = port
        comps.path = path
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url
    }

    func wsURL(_ path: String, query: [String: String] = [:]) -> URL? {
        var q = query
        q["token"] = token
        return url(scheme: "ws", path: path, query: q)
    }

    private func makeRequest(_ path: String, query: [String: String], method: String, body: [String: Any]?) throws -> URLRequest {
        guard let u = url(scheme: "http", path: path, query: query) else { throw AgentError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private static func checkStatus(_ resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AgentError.http(http.statusCode)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: makeRequest(path, query: query, method: "GET", body: nil))
        try Self.checkStatus(resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any] = [:], as type: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: makeRequest(path, query: [:], method: "POST", body: body))
        try Self.checkStatus(resp)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
