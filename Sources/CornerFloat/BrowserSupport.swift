import Foundation

enum BrowserSupport {
    enum ExternalNavigationDisposition: Equatable {
        case block
        case confirmBeforeOpening
    }

    enum ConnectionSecurityState: Equatable {
        case secure
        case insecure
        case localContent
    }

    enum FailureKind: Equatable {
        case offline
        case timedOut
        case dns
        case tls
        case accessDenied
        case generic
    }

    static func safeSuggestedFilename(_ suggestedFilename: String) -> String {
        let component = (suggestedFilename as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !component.isEmpty, component != ".", component != ".." else {
            return "Download"
        }
        return component.replacingOccurrences(of: ":", with: "-")
    }

    static func failureKind(for error: Error) -> FailureKind {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .generic }
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .offline
        case NSURLErrorTimedOut:
            return .timedOut
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dns
        case NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .tls
        case NSURLErrorUserAuthenticationRequired, NSURLErrorNoPermissionsToReadFile:
            return .accessDenied
        default:
            return .generic
        }
    }

    static func isWebURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Only replay requests whose semantics are read-only. In particular, an
    /// authentication or payment POST must not be submitted twice after a
    /// connection failure.
    static func isSafeToRetry(_ request: URLRequest?) -> Bool {
        guard let request,
              request.httpBody == nil,
              request.httpBodyStream == nil else { return false }
        switch (request.httpMethod ?? "GET").uppercased() {
        case "GET", "HEAD":
            return true
        default:
            return false
        }
    }

    /// Google requires a browser to identify itself clearly rather than claim
    /// to be Chrome, Safari, or another product. WKWebView appends this token
    /// to its engine-generated user agent without replacing or spoofing it.
    static func browserApplicationName(version: String?) -> String {
        let rawVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeVersion = (rawVersion?.isEmpty == false ? rawVersion! : "development")
            .map { character in
                character.isLetter || character.isNumber || ".-_".contains(character)
                    ? character
                    : "-"
            }
        return "CornerFloat/\(String(safeVersion))"
    }

    static func connectionSecurityState(
        for url: URL?,
        hasOnlySecureContent: Bool,
        hasServerTrust: Bool
    ) -> ConnectionSecurityState {
        switch url?.scheme?.lowercased() {
        case "https":
            return hasOnlySecureContent && hasServerTrust ? .secure : .insecure
        case "http":
            return .insecure
        default:
            return .localContent
        }
    }

    static func externalNavigationDisposition(
        for url: URL?,
        isUserInitiated: Bool,
        isMainFrame: Bool
    ) -> ExternalNavigationDisposition {
        guard let scheme = url?.scheme?.lowercased(),
              !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) else {
            return .block
        }
        // A click is useful evidence of intent, but it is not consent to launch
        // an arbitrary external application. Keep background/subframe requests
        // blocked and require an explicit CornerFloat confirmation for every
        // external main-frame transition, including user-initiated links.
        return (isUserInitiated || isMainFrame) ? .confirmBeforeOpening : .block
    }
}
