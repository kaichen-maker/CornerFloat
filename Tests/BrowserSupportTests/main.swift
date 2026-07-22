import Foundation

private func fail(_ message: String) -> Never {
    fputs("CornerFloat browser-support test failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fail(message) }
}

expect(
    SmartAddressResolver.resolve("ChatGPT")?.absoluteString
        == "https://chatgpt.com/auth/login",
    "ChatGPT shortcut"
)
expect(
    SmartAddressResolver.resolve("Gmail")?.absoluteString == "https://mail.google.com/",
    "Gmail shortcut"
)
let unimailURL = SmartAddressResolver.resolve("UniMail")
let unimailQuery = unimailURL.flatMap {
    URLComponents(url: $0, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "q" })?.value
}
expect(unimailQuery == "UniMail", "UniMail search query")

let customShortcut = AddressShortcut(
    id: UUID(),
    name: "University Mail",
    aliases: ["UniMail", "Campus Mail"],
    url: "https://mail.google.com/",
    createdAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 0)
)
expect(
    SmartAddressResolver.resolve("uni mail", customShortcuts: [customShortcut])?.absoluteString
        == "https://mail.google.com/",
    "custom shortcut normalization"
)
let invalidCustomShortcut = AddressShortcut(
    id: UUID(),
    name: "Unsafe",
    aliases: ["Unsafe Alias"],
    url: "javascript:alert(1)",
    createdAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 0)
)
let invalidShortcutResult = SmartAddressResolver.resolve(
    "Unsafe Alias",
    customShortcuts: [invalidCustomShortcut]
)
expect(
    invalidShortcutResult?.host == "www.google.com",
    "invalid custom shortcut must fall back to search"
)

expect(BrowserSupport.safeSuggestedFilename("../../secret.txt") == "secret.txt", "path traversal")
expect(BrowserSupport.safeSuggestedFilename("folder/report.pdf") == "report.pdf", "nested path")
expect(BrowserSupport.safeSuggestedFilename("..") == "Download", "empty path component")
expect(BrowserSupport.safeSuggestedFilename("report:final.pdf") == "report-final.pdf", "colon")

expect(
    BrowserSupport.failureKind(for: URLError(.notConnectedToInternet)) == .offline,
    "offline classification"
)
expect(BrowserSupport.failureKind(for: URLError(.timedOut)) == .timedOut, "timeout classification")
expect(BrowserSupport.failureKind(for: URLError(.cannotFindHost)) == .dns, "DNS classification")
expect(
    BrowserSupport.failureKind(for: URLError(.serverCertificateUntrusted)) == .tls,
    "TLS classification"
)

expect(BrowserSupport.isSafeToRetry(URLRequest(url: URL(string: "https://example.com")!)), "GET retry")
var headRequest = URLRequest(url: URL(string: "https://example.com")!)
headRequest.httpMethod = "HEAD"
expect(BrowserSupport.isSafeToRetry(headRequest), "HEAD retry")
var postRequest = URLRequest(url: URL(string: "https://example.com/sign-in")!)
postRequest.httpMethod = "POST"
postRequest.httpBody = Data("credential=private".utf8)
expect(!BrowserSupport.isSafeToRetry(postRequest), "POST must not be replayed")
var getWithBody = URLRequest(url: URL(string: "https://example.com/unusual")!)
getWithBody.httpMethod = "GET"
getWithBody.httpBody = Data("must-not-replay".utf8)
expect(!BrowserSupport.isSafeToRetry(getWithBody), "GET with a body must not be replayed")
var implicitMethodWithBody = URLRequest(url: URL(string: "https://example.com/unusual")!)
implicitMethodWithBody.httpBody = Data("must-not-replay".utf8)
expect(!BrowserSupport.isSafeToRetry(implicitMethodWithBody), "implicit method with a body must not be replayed")
expect(
    BrowserSupport.browserApplicationName(version: "0.6.1 beta")
        == "CornerFloat/0.6.1-beta",
    "browser user agent must identify CornerFloat without claiming another browser"
)
expect(
    BrowserSupport.browserApplicationName(version: nil)
        == "CornerFloat/development",
    "development browser user agent"
)
expect(
    BrowserSupport.connectionSecurityState(
        for: URL(string: "https://accounts.google.com/"),
        hasOnlySecureContent: true,
        hasServerTrust: true
    ) == .secure,
    "trusted HTTPS connection"
)
expect(
    BrowserSupport.connectionSecurityState(
        for: URL(string: "https://example.com/"),
        hasOnlySecureContent: true,
        hasServerTrust: false
    ) == .insecure,
    "HTTPS without server trust must not look secure"
)
expect(
    BrowserSupport.connectionSecurityState(
        for: URL(string: "http://example.com/"),
        hasOnlySecureContent: false,
        hasServerTrust: false
    ) == .insecure,
    "HTTP connection"
)
expect(
    BrowserSupport.connectionSecurityState(
        for: URL(string: "about:blank"),
        hasOnlySecureContent: false,
        hasServerTrust: false
    ) == .localContent,
    "internal content connection state"
)

expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "https",
        capture: .microphone
    ) == .prompt,
    "HTTPS microphone capture must ask the user"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "HTTPS",
        capture: .microphone
    ) == .prompt,
    "media-capture scheme matching must be case-insensitive"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "http",
        capture: .microphone
    ) == .deny,
    "insecure microphone capture must be denied"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: nil,
        capture: .microphone
    ) == .deny,
    "microphone capture without a security scheme must be denied"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "https",
        capture: .camera
    ) == .deny,
    "camera capture is outside CornerFloat's permission boundary"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "https",
        capture: .cameraAndMicrophone
    ) == .deny,
    "combined camera and microphone capture must not bypass the camera denial"
)
expect(
    BrowserSupport.mediaCaptureDecision(
        scheme: "https",
        capture: .unknown
    ) == .deny,
    "unknown capture types must fail closed"
)

let callback = URL(string: "microsoft-edge://oauth/callback")!
expect(
    BrowserSupport.externalNavigationDisposition(
        for: callback,
        isUserInitiated: true,
        isMainFrame: true
    ) == .confirmBeforeOpening,
    "user-initiated external callback confirmation"
)
expect(
    BrowserSupport.externalNavigationDisposition(
        for: callback,
        isUserInitiated: false,
        isMainFrame: true
    ) == .confirmBeforeOpening,
    "automatic main-frame callback confirmation"
)
expect(
    BrowserSupport.externalNavigationDisposition(
        for: callback,
        isUserInitiated: false,
        isMainFrame: false
    ) == .block,
    "automatic subframe callback"
)
expect(
    BrowserSupport.externalNavigationDisposition(
        for: URL(string: "file:///tmp/private.txt"),
        isUserInitiated: true,
        isMainFrame: true
    ) == .block,
    "file URL from a web page"
)
expect(
    BrowserSupport.externalNavigationDisposition(
        for: URL(string: "javascript:alert(1)"),
        isUserInitiated: true,
        isMainFrame: true
    ) == .block,
    "JavaScript URL from a web page"
)

print("CornerFloat browser-support tests OK: resolution, downloads, errors, media capture and external schemes")
