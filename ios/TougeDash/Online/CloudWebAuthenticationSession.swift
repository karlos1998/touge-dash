import AuthenticationServices
import UIKit

@MainActor
final class CloudWebAuthenticationSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(webAddress: String, provider: String) async throws -> String {
        guard var components = URLComponents(string: webAddress),
              components.scheme == "https" || components.scheme == "http",
              components.host != nil else {
            throw CloudAPIError.invalidServerAddress
        }
        components.path = "/auth"
        components.queryItems = [
            URLQueryItem(name: "mobileReturn", value: "tougedash://auth"),
            URLQueryItem(name: "provider", value: provider)
        ]
        guard let url = components.url else { throw CloudAPIError.invalidServerAddress }

        return try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "tougedash"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error); return }
                    guard let callbackURL,
                          let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value,
                          !code.isEmpty else {
                        continuation.resume(throwing: CloudAPIError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: code)
                }
            }
            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            session = authenticationSession
            if !authenticationSession.start() {
                session = nil
                continuation.resume(throwing: CloudAPIError.invalidResponse)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
