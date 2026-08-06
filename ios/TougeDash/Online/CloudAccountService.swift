import Foundation

@MainActor
final class CloudAccountService: ObservableObject {
    private enum Defaults {
        static let serverAddress = "TougeDash.cloud.serverAddress"
        static let webAddress = "TougeDash.cloud.webAddress"
        static let productionServerAddress = "https://touge-dash-engine.letscode.it"
        static let productionWebAddress = "https://touge-dash.letscode.it"
    }

    @Published private(set) var session: CloudAuthSession?
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?
    @Published var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Defaults.serverAddress) }
    }
    @Published var webAddress: String {
        didSet { UserDefaults.standard.set(webAddress, forKey: Defaults.webAddress) }
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        session = CloudCredentialStore.load()
#if DEBUG
        serverAddress = Self.resolvedAddress(
            UserDefaults.standard.string(forKey: Defaults.serverAddress),
            productionAddress: Defaults.productionServerAddress
        )
        webAddress = Self.resolvedAddress(
            UserDefaults.standard.string(forKey: Defaults.webAddress),
            productionAddress: Defaults.productionWebAddress
        )
#else
        serverAddress = Defaults.productionServerAddress
        webAddress = Defaults.productionWebAddress
#endif
        UserDefaults.standard.set(serverAddress, forKey: Defaults.serverAddress)
        UserDefaults.standard.set(webAddress, forKey: Defaults.webAddress)
    }

    var isAuthenticated: Bool { session != nil }
    var account: CloudAccount? { session?.account }

    nonisolated static func resolvedAddress(_ storedAddress: String?, productionAddress: String) -> String {
        guard let storedAddress = storedAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storedAddress.isEmpty,
              let host = URLComponents(string: storedAddress)?.host?.lowercased(),
              !["localhost", "127.0.0.1", "::1"].contains(host) else {
            return productionAddress
        }
        return storedAddress
    }

    func register(email: String, password: String, displayName: String) async -> Bool {
        await authenticate(endpoint: "/api/v1/auth/register", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    func login(email: String, password: String) async -> Bool {
        await authenticate(endpoint: "/api/v1/auth/login", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ])
    }

    func signInWithApple(identityToken: String, displayName: String?) async -> Bool {
        struct SocialRequest: Encodable {
            let provider: String
            let token: String
            let displayName: String?
        }
        return await authenticate(
            endpoint: "/api/v1/auth/social",
            body: SocialRequest(provider: "APPLE", token: identityToken, displayName: displayName)
        )
    }

    func exchangeMobileHandoff(code: String) async -> Bool {
        struct Request: Encodable { let code: String }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let authenticated: CloudAuthSession = try await sendWithoutAuthorization(
                endpoint: "/api/v1/auth/mobile-handoff/exchange",
                method: "POST",
                body: Request(code: code),
                response: CloudAuthSession.self
            )
            try accept(authenticated)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func logout() async {
        let token = session?.refreshToken
        session = nil
        CloudCredentialStore.clear()
        if let token {
            struct LogoutBody: Encodable { let refreshToken: String }
            _ = try? await sendWithoutAuthorization(
                endpoint: "/api/v1/auth/logout",
                method: "POST",
                body: LogoutBody(refreshToken: token),
                response: EmptyCloudResponse.self
            )
        }
    }

    func deleteAccount() async -> Bool {
        guard session != nil else { return true }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let _: EmptyCloudResponse = try await sendAuthorized(
                endpoint: "/api/v1/me",
                method: "DELETE",
                body: nil,
                response: EmptyCloudResponse.self
            )
            session = nil
            CloudCredentialStore.clear()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clearError() {
        lastError = nil
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    func send<Response: Decodable, Body: Encodable>(
        endpoint: String,
        method: String = "POST",
        body: Body,
        response: Response.Type = Response.self
    ) async throws -> Response {
        let data = try JSONEncoder.tougeDashCloud().encode(body)
        return try await sendAuthorized(endpoint: endpoint, method: method, body: data, response: response)
    }

    func get<Response: Decodable>(endpoint: String, response: Response.Type = Response.self) async throws -> Response {
        try await sendAuthorized(endpoint: endpoint, method: "GET", body: nil, response: response)
    }

    func delete(endpoint: String) async throws {
        let _: EmptyCloudResponse = try await sendAuthorized(
            endpoint: endpoint,
            method: "DELETE",
            body: nil,
            response: EmptyCloudResponse.self
        )
    }

    private func authenticate<Body: Encodable>(endpoint: String, body: Body) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let authenticated: CloudAuthSession = try await sendWithoutAuthorization(
                endpoint: endpoint,
                method: "POST",
                body: body,
                response: CloudAuthSession.self
            )
            try accept(authenticated)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func sendWithoutAuthorization<Response: Decodable, Body: Encodable>(
        endpoint: String,
        method: String,
        body: Body,
        response: Response.Type
    ) async throws -> Response {
        let data = try JSONEncoder.tougeDashCloud().encode(body)
        return try await perform(endpoint: endpoint, method: method, body: data, bearer: nil, response: response)
    }

    private func sendAuthorized<Response: Decodable>(
        endpoint: String,
        method: String,
        body: Data?,
        response: Response.Type
    ) async throws -> Response {
        guard let token = session?.accessToken else { throw CloudAPIError.unauthorized }
        do {
            return try await perform(endpoint: endpoint, method: method, body: body, bearer: token, response: response)
        } catch CloudAPIError.unauthorized {
            try await refreshSession()
            guard let refreshed = session?.accessToken else { throw CloudAPIError.unauthorized }
            return try await perform(endpoint: endpoint, method: method, body: body, bearer: refreshed, response: response)
        }
    }

    private func refreshSession() async throws {
        guard let refreshToken = session?.refreshToken else { throw CloudAPIError.unauthorized }
        struct RefreshBody: Encodable { let refreshToken: String }
        do {
            let refreshed: CloudAuthSession = try await sendWithoutAuthorization(
                endpoint: "/api/v1/auth/refresh",
                method: "POST",
                body: RefreshBody(refreshToken: refreshToken),
                response: CloudAuthSession.self
            )
            try CloudCredentialStore.save(refreshed)
            session = refreshed
        } catch {
            session = nil
            CloudCredentialStore.clear()
            throw CloudAPIError.unauthorized
        }
    }

    private func perform<Response: Decodable>(
        endpoint: String,
        method: String,
        body: Data?,
        bearer: String?,
        response: Response.Type
    ) async throws -> Response {
        guard let baseURL = normalizedBaseURL(),
              let url = URL(string: endpoint, relativeTo: baseURL)?.absoluteURL else {
            throw CloudAPIError.invalidServerAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        let (data, urlResponse) = try await urlSession.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw CloudAPIError.invalidResponse }
        if http.statusCode == 401 { throw CloudAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder.tougeDashCloud().decode(CloudAPIErrorPayload.self, from: data)
            throw CloudAPIError.server(
                status: http.statusCode,
                message: payload?.message ?? String(format: localized("Błąd serwera (%d)."), http.statusCode)
            )
        }
        if Response.self == EmptyCloudResponse.self {
            return EmptyCloudResponse() as! Response
        }
        return try JSONDecoder.tougeDashCloud().decode(Response.self, from: data)
    }

    private func normalizedBaseURL() -> URL? {
        let value = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              components.scheme == "https" || components.scheme == "http",
              components.host != nil else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    private func accept(_ authenticated: CloudAuthSession) throws {
        try CloudCredentialStore.save(authenticated)
        session = authenticated
    }
}

struct EmptyCloudResponse: Decodable, Sendable { }
