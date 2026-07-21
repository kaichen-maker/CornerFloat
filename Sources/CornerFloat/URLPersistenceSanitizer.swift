import Foundation

/// Produces a privacy-safe URL for durable storage without changing the URL
/// that WebKit actually loads. Authentication callbacks commonly carry
/// short-lived credentials in user info, fragments, or query parameters; none
/// of those values belong in preferences, favorites, recents, or workspaces.
enum URLPersistenceSanitizer {
    static let maximumPersistedURLLength = 4_096

    private static let sensitiveQueryKeys: Set<String> = [
        "access_token",
        "api_key",
        "apikey",
        "assertion",
        "auth",
        "authorization",
        "client_secret",
        "code",
        "credential",
        "id_token",
        "key",
        "oauth_token",
        "password",
        "passwd",
        "refresh_token",
        "samlresponse",
        "secret",
        "session_token",
        "state",
        "token"
    ]

    static func sanitizedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else { return nil }

        components.user = nil
        components.password = nil
        components.fragment = nil

        if components.percentEncodedQuery != nil {
            guard let queryItems = components.queryItems else { return nil }
            let retainedItems = queryItems.filter {
                !sensitiveQueryKeys.contains($0.name.lowercased())
            }
            components.queryItems = retainedItems.isEmpty ? nil : retainedItems
        }

        guard let sanitizedURL = components.url,
              sanitizedURL.absoluteString.utf8.count <= maximumPersistedURLLength else {
            return nil
        }
        return sanitizedURL
    }
}

enum URLPersistenceSanitizerSelfTest {
    static func run() -> String? {
        guard let searchURL = URL(
            string: "https://www.google.com/search?q=CornerFloat%20privacy&hl=en#results"
        ), let sanitizedSearchURL = URLPersistenceSanitizer.sanitizedURL(searchURL),
           let searchComponents = URLComponents(
               url: sanitizedSearchURL,
               resolvingAgainstBaseURL: false
           ) else {
            return "ordinary search URL could not be sanitized"
        }
        guard searchComponents.fragment == nil,
              searchComponents.queryItems == [
                  URLQueryItem(name: "q", value: "CornerFloat privacy"),
                  URLQueryItem(name: "hl", value: "en")
              ] else {
            return "ordinary search query parameters were not preserved"
        }

        guard let mixedCaseURL = URL(
            string: "https://alice:password@example.com/callback?CoDe=one&ACCESS_TOKEN=two&SamlResponse=three&STATE=four&q=kept#id_token=five"
        ), let sanitizedMixedCaseURL = URLPersistenceSanitizer.sanitizedURL(mixedCaseURL),
           let mixedCaseComponents = URLComponents(
               url: sanitizedMixedCaseURL,
               resolvingAgainstBaseURL: false
        ) else {
            return "mixed-case authentication URL could not be sanitized"
        }
        let mixedCaseText = sanitizedMixedCaseURL.absoluteString.lowercased()
        guard mixedCaseComponents.user == nil,
              mixedCaseComponents.password == nil,
              mixedCaseComponents.fragment == nil,
              mixedCaseComponents.queryItems == [URLQueryItem(name: "q", value: "kept")],
              !mixedCaseText.contains("password"),
              !mixedCaseText.contains("access_token"),
              !mixedCaseText.contains("samlresponse") else {
            return "authentication data survived case-insensitive sanitization"
        }

        guard let callbackURL = URL(
            string: "https://login.example/callback?code=secret&id_token=secret&refresh_token=secret&token=secret&assertion=secret&state=secret#access_token=secret"
        ), let sanitizedCallbackURL = URLPersistenceSanitizer.sanitizedURL(callbackURL),
           sanitizedCallbackURL.absoluteString == "https://login.example/callback" else {
            return "authentication callback retained transient credentials"
        }

        guard URLPersistenceSanitizer.sanitizedURL(
            URL(string: "file:///tmp/private")!
        ) == nil else {
            return "non-web URL was accepted for persistence"
        }

        let overlongURL = URL(
            string: "https://example.com/search?q=\(String(repeating: "a", count: 5_000))"
        )!
        guard URLPersistenceSanitizer.sanitizedURL(overlongURL) == nil else {
            return "overlong URL was accepted for persistence"
        }

        return nil
    }
}
