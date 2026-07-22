import AppKit
import Darwin
import Foundation
import WebKit

/// The integration binary compiles the production WebPanelController and its
/// direct dependencies. This deliberately tiny owner replaces the rest of the
/// application graph so the suite tests the real browser controller without
/// starting Sparkle, status items, or onboarding windows.
@MainActor
final class AppController {
    func requestMenuRefresh() {}
    func index(of panel: FloatingPanelController) -> Int { 0 }
    func panelDidClose(_ panel: FloatingPanelController) {}
    func resolveAddress(_ input: String) -> URL? { SmartAddressResolver.resolve(input) }
}

private struct CapturedHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

/// A deliberately small HTTP/1.1 fixture bound to 127.0.0.1. It keeps the
/// integration suite offline while still exercising WebKit's network process,
/// cookie store, form submission, response policy and download pipeline.
private final class LocalHTTPFixture: @unchecked Sendable {
    enum FixtureError: Error, CustomStringConvertible {
        case socket(Int32)
        case bind(Int32)
        case listen(Int32)
        case address(Int32)

        var description: String {
            let operation: String
            let code: Int32
            switch self {
            case .socket(let value): (operation, code) = ("socket", value)
            case .bind(let value): (operation, code) = ("bind 127.0.0.1", value)
            case .listen(let value): (operation, code) = ("listen", value)
            case .address(let value): (operation, code) = ("getsockname", value)
            }
            return "\(operation) failed: \(String(cString: strerror(code))) (\(code))"
        }
    }

    private struct HTTPResponse {
        let status: Int
        let reason: String
        let headers: [String: String]
        let body: Data
    }

    let port: UInt16
    let cookieToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private let stateLock = NSLock()
    private var requests: [CapturedHTTPRequest] = []
    private var listeningDescriptor: Int32
    private var isStopped = false
    private let acceptQueue = DispatchQueue(label: "CornerFloat.WebKitTests.HTTP.accept")
    private let clientQueue = DispatchQueue(
        label: "CornerFloat.WebKitTests.HTTP.clients",
        attributes: .concurrent
    )

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw FixtureError.socket(errno) }

        var reuse: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout.size(ofValue: reuse))
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw FixtureError.bind(code)
        }
        guard Darwin.listen(descriptor, 16) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw FixtureError.listen(code)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let addressResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard addressResult == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw FixtureError.address(code)
        }

        listeningDescriptor = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
        acceptQueue.async { [weak self] in
            self?.acceptConnections()
        }
    }

    deinit {
        stop()
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    func requestCount(method: String, path: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requests.filter { $0.method == method && $0.path == path }.count
    }

    func lastRequest(method: String, path: String) -> CapturedHTTPRequest? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requests.last { $0.method == method && $0.path == path }
    }

    func stop() {
        stateLock.lock()
        guard !isStopped else {
            stateLock.unlock()
            return
        }
        isStopped = true
        let descriptor = listeningDescriptor
        listeningDescriptor = -1
        stateLock.unlock()
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func acceptConnections() {
        while true {
            stateLock.lock()
            let descriptor = listeningDescriptor
            let stopped = isStopped
            stateLock.unlock()
            guard !stopped, descriptor >= 0 else { return }

            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            clientQueue.async { [weak self] in
                self?.handle(client)
            }
        }
    }

    private func handle(_ descriptor: Int32) {
        defer {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }

        guard let request = readRequest(from: descriptor) else { return }
        stateLock.lock()
        requests.append(request)
        stateLock.unlock()

        let response = response(for: request)
        var headerLines = [
            "HTTP/1.1 \(response.status) \(response.reason)",
            "Content-Length: \(response.body.count)",
            "Connection: close",
            "Cache-Control: no-store"
        ]
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            headerLines.append("\(name): \(value)")
        }
        let head = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        sendAll(head + response.body, to: descriptor)
    }

    private func readRequest(from descriptor: Int32) -> CapturedHTTPRequest? {
        var received = Data()
        var expectedSize: Int?
        let separator = Data("\r\n\r\n".utf8)

        while received.count < 1_048_576 {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            received.append(buffer, count: count)

            if let range = received.range(of: separator) {
                if expectedSize == nil,
                   let header = String(data: received[..<range.lowerBound], encoding: .utf8) {
                    let contentLength = header
                        .components(separatedBy: "\r\n")
                        .dropFirst()
                        .compactMap { line -> Int? in
                            let parts = line.split(separator: ":", maxSplits: 1)
                            guard parts.count == 2,
                                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                                    .lowercased() == "content-length" else { return nil }
                            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .first ?? 0
                    expectedSize = range.upperBound + contentLength
                }
                if let expectedSize, received.count >= expectedSize { break }
            }
        }

        guard let headerRange = received.range(of: separator),
              let headerText = String(data: received[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let target = requestParts[1]
        let components = URLComponents(string: "http://fixture\(target)")
        let body = Data(received[headerRange.upperBound...])
        return CapturedHTTPRequest(
            method: requestParts[0].uppercased(),
            path: components?.path ?? target,
            headers: headers,
            body: body
        )
    }

    private func response(for request: CapturedHTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/set-cookie"):
            return html(
                "<title>Cookie Source</title><body>cookie set</body>",
                headers: [
                    "Set-Cookie": "CornerFloatIntegration=\(cookieToken); Path=/; SameSite=Lax"
                ]
            )
        case ("GET", "/read-cookie"):
            let cookie = htmlEscaped(request.headers["cookie"] ?? "")
            return html("<title>Cookie Reader</title><body id='cookie'>\(cookie)</body>")
        case ("GET", "/popup-source"):
            return html("<title>Popup Source</title><body>source</body>")
        case ("GET", "/popup-child"):
            return html("<title>Popup Child</title><body>child</body>")
        case ("GET", "/get-failure"):
            return html(
                "<title>GET Failed</title><body>temporary failure</body>",
                status: 503,
                reason: "Service Unavailable"
            )
        case ("GET", "/post-form"):
            return html(
                """
                <title>POST Form</title>
                <form id='post' method='post' action='/post-failure'>
                  <input name='token' value='send-once'>
                </form>
                """
            )
        case ("POST", "/post-failure"):
            return html(
                "<title>POST Failed</title><body>do not replay</body>",
                status: 503,
                reason: "Service Unavailable"
            )
        case ("GET", "/root"):
            return html("<title>Root</title><body>ready</body>")
        case ("GET", "/dialogs"):
            return html(
                """
                <title>Dialogs</title><body data-result='pending'>ready</body>
                <script>
                function runDialogs() {
                  alert('integration alert');
                  const accepted = confirm('integration confirm');
                  const answer = prompt('integration prompt', 'default');
                  document.body.dataset.result = accepted + ':' + answer;
                  return document.body.dataset.result;
                }
                </script>
                """
            )
        case ("GET", "/upload"):
            return html(
                "<title>Upload</title><input id='upload' type='file' multiple>"
            )
        case ("GET", "/download"):
            return HTTPResponse(
                status: 200,
                reason: "OK",
                headers: [
                    "Content-Type": "text/plain",
                    "Content-Disposition": "attachment; filename=integration-download.txt"
                ],
                body: Data("CornerFloat offline download".utf8)
            )
        default:
            return html("<title>Not Found</title>", status: 404, reason: "Not Found")
        }
    }

    private func html(
        _ body: String,
        status: Int = 200,
        reason: String = "OK",
        headers: [String: String] = [:]
    ) -> HTTPResponse {
        var headers = headers
        headers["Content-Type"] = "text/html; charset=utf-8"
        return HTTPResponse(status: status, reason: reason, headers: headers, body: Data(body.utf8))
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func sendAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let sent = Darwin.send(descriptor, base.advanced(by: offset), rawBuffer.count - offset, 0)
                guard sent > 0 else { return }
                offset += sent
            }
        }
    }
}

@MainActor
private final class RecordingUIDelegate: NSObject, WKUIDelegate {
    private(set) var alertMessages: [String] = []
    private(set) var confirmMessages: [String] = []
    private(set) var promptMessages: [(String, String?)] = []
    private(set) var uploadRequestCount = 0
    private(set) var uploadAllowsMultipleSelection = false

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback0
    ) {
        alertMessages.append(message)
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<Bool>
    ) {
        confirmMessages.append(message)
        completionHandler(true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<String?>
    ) {
        promptMessages.append((prompt, defaultText))
        completionHandler("delegate answer")
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<[URL]?>
    ) {
        uploadRequestCount += 1
        uploadAllowsMultipleSelection = parameters.allowsMultipleSelection
        completionHandler(nil)
    }
}

@MainActor
private final class RecordingDownloadDelegate: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let destination: URL
    private(set) var didBecomeDownload = false
    private(set) var isFinished = false
    private(set) var suggestedFilename: String?
    private(set) var failure: Error?
    private var activeDownload: WKDownload?

    init(destination: URL) {
        self.destination = destination
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping WebKitCallback1<WKNavigationResponsePolicy>
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(disposition.contains("attachment") ? .download : .allow)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        didBecomeDownload = true
        activeDownload = download
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping WebKitCallback1<URL?>
    ) {
        self.suggestedFilename = suggestedFilename
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        activeDownload = nil
        isFinished = true
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        activeDownload = nil
        failure = error
        isFinished = true
    }
}

private enum IntegrationTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
@MainActor
private struct WebKitIntegrationTestRunner {
    static func main() async {
        _ = NSApplication.shared
        do {
            try await testProductionPanelSharesPersistentCookiesAndPreservesPopupOpener()
            try await testProductionWorkspaceProjectionTabAccessibilityAndCycling()
            try await testProductionTabLimitBlocksWebsitePopups()
            try await testProductionPanelTracksGETAndPOSTFailuresWithoutReplayingPOST()
            try await testProductionWebProcessTerminationHandlerHasRecoverableState()
            try await testRealWKWebViewInvokesJavaScriptAndUploadUIDelegates()
            try await testRealWKDownloadDelegateWritesOfflineAttachment()
            try expect(
                integrationCookieValuesSynchronously(from: .default()).isEmpty,
                "integration cookies leaked into the persistent WebKit store"
            )
            print("CornerFloat WebKit integration tests OK: persistent cross-tab cookies, popup opener, workspace projection, accessible tab state, tab cycling, live-tab limits, dialogs, upload, download, GET/POST recovery and process-termination handling")
        } catch {
            fputs("CornerFloat WebKit integration test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testProductionPanelSharesPersistentCookiesAndPreservesPopupOpener() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let owner = AppController()
        let panel = WebPanelController(owner: owner, url: fixture.url("/set-cookie"))
        defer {
            removeIntegrationCookiesSynchronously(
                from: panel.integrationTabStates.first?.webView.configuration.websiteDataStore
                    ?? WKWebsiteDataStore.default(),
                matchingValue: fixture.cookieToken
            )
            panel.close()
        }

        let firstWebView = try require(
            panel.selectedIntegrationWebView,
            "production panel did not create its first WKWebView"
        )
        try await waitForPath("/set-cookie", in: firstWebView)
        try expect(firstWebView.configuration.websiteDataStore.isPersistent, "production data store is not persistent")
        try expect(firstWebView.navigationDelegate === panel, "production navigation delegate is not wired")
        try expect(firstWebView.uiDelegate === panel, "production UI delegate is not wired")
        let mediaCaptureSelector = NSSelectorFromString(
            "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:"
        )
        try expect(
            panel.responds(to: mediaCaptureSelector),
            "production UI delegate does not expose the website media-capture callback"
        )
        let expectedBrowserProduct = BrowserSupport.browserApplicationName(
            version: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
        try expect(
            firstWebView.configuration.applicationNameForUserAgent == expectedBrowserProduct,
            "production WebKit configuration does not identify CornerFloat"
        )
        let userAgent = try await javaScriptString("navigator.userAgent", in: firstWebView)
        try expect(
            userAgent.contains(expectedBrowserProduct),
            "rendered page user-agent omits the CornerFloat product token"
        )
        try expect(
            !userAgent.contains("Chrome/") && !userAgent.contains("Firefox/"),
            "CornerFloat must not claim another browser identity"
        )
        try await waitUntil("source-tab cookie commit") {
            (try? awaitJavaScriptBool(
                "document.cookie.includes('\(fixture.cookieToken)')",
                in: firstWebView
            )) == true
        }
        try await waitUntil("persistent cookie-store commit") {
            integrationCookieValuesSynchronously(
                from: firstWebView.configuration.websiteDataStore
            ).contains(fixture.cookieToken)
        }

        panel.openNewTab(url: fixture.url("/read-cookie"))
        try await waitUntil("second production tab") { panel.integrationTabStates.count == 2 }
        let cookieReader = try require(
            panel.selectedIntegrationWebView,
            "production panel did not select the cookie-reader tab"
        )
        try await waitForPath("/read-cookie", in: cookieReader)
        try await waitUntil("cookie visibility in second production tab") {
            (try? awaitJavaScriptBool(
                "document.cookie.includes('\(fixture.cookieToken)')",
                in: cookieReader
            )) == true
        }
        let cookieText = try await javaScriptString("document.cookie", in: cookieReader)
        try expect(
            cookieText.contains(fixture.cookieToken),
            "a cookie set in one production tab was not visible in another"
        )

        panel.openNewTab(url: fixture.url("/popup-source"))
        let opener = try require(
            panel.selectedIntegrationWebView,
            "production panel did not create the popup source tab"
        )
        try await waitForPath("/popup-source", in: opener)
        let popupURL = fixture.url("/popup-child").absoluteString
        _ = try await opener.evaluateJavaScript(
            "window.open('\(popupURL)', '_blank'); 'opened'"
        )
        try await waitUntil("window.open production tab") { panel.integrationTabStates.count == 4 }
        let popup = try require(
            panel.selectedIntegrationWebView,
            "production panel did not select the popup tab"
        )
        try await waitForPath("/popup-child", in: popup)
        let hasOpener = try await javaScriptBool("window.opener !== null", in: popup)
        try expect(hasOpener, "popup lost window.opener")
        let openerPath = try await javaScriptString("window.opener.location.pathname", in: popup)
        try expect(openerPath == "/popup-source", "popup points to the wrong opener")
        let popupCookie = try await javaScriptString("document.cookie", in: popup)
        try expect(
            popupCookie.contains(fixture.cookieToken),
            "the WebKit-supplied popup configuration lost the persistent cookie store"
        )
        try expect(popup.navigationDelegate === panel, "popup navigation delegate is not wired")
        try expect(popup.uiDelegate === panel, "popup UI delegate is not wired")
        print("  PASS production persistent cookie and window.open/opener")
    }

    private static func testProductionPanelTracksGETAndPOSTFailuresWithoutReplayingPOST() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let owner = AppController()
        let panel = WebPanelController(owner: owner, url: fixture.url("/get-failure"))
        defer { panel.close() }

        let getWebView = try require(panel.selectedIntegrationWebView, "missing GET web view")
        try await waitForFailure(
            method: "GET",
            path: "/get-failure",
            webView: getWebView,
            panel: panel,
            fixture: fixture
        )
        let firstGETState = try require(state(for: getWebView, in: panel), "missing GET state")
        try expect(firstGETState.failedRequest?.httpMethod == "GET", "failed GET method was not tracked")
        try expect(firstGETState.failedURL?.path == "/get-failure", "failed GET URL was not tracked")
        try expect(firstGETState.isShowingError, "failed GET did not show recovery UI")
        try expect(BrowserSupport.isSafeToRetry(firstGETState.failedRequest), "GET should be retryable")

        panel.reloadCurrentPage()
        try await waitUntil("safe GET retry") {
            fixture.requestCount(method: "GET", path: "/get-failure") >= 2
        }

        panel.openNewTab(url: fixture.url("/post-form"))
        let postWebView = try require(panel.selectedIntegrationWebView, "missing POST web view")
        try await waitForPath("/post-form", in: postWebView)
        try await waitUntil("POST form DOM marker") {
            (try? awaitJavaScriptBool(
                "document.getElementById('post') !== null",
                in: postWebView
            )) == true
        }
        _ = try await postWebView.evaluateJavaScript("document.getElementById('post').submit(); 'submitted'")
        try await waitForFailure(
            method: "POST",
            path: "/post-failure",
            webView: postWebView,
            panel: panel,
            fixture: fixture
        )

        let postState = try require(state(for: postWebView, in: panel), "missing POST state")
        try expect(postState.failedRequest?.httpMethod == "POST", "failed POST method was not tracked")
        try expect(postState.failedURL?.path == "/post-failure", "failed POST URL was not tracked")
        try expect(postState.isShowingError, "failed POST did not show recovery UI")
        try expect(!BrowserSupport.isSafeToRetry(postState.failedRequest), "POST was marked safe to replay")
        try expect(
            fixture.lastRequest(method: "POST", path: "/post-failure")?.body == Data("token=send-once".utf8),
            "fixture did not receive the expected form body"
        )

        panel.reloadCurrentPage()
        try await Task.sleep(nanoseconds: 500_000_000)
        try expect(
            fixture.requestCount(method: "POST", path: "/post-failure") == 1,
            "the production retry command resubmitted a failed POST"
        )
        print("  PASS production GET retry and POST replay prevention")
    }

    private static func testProductionWorkspaceProjectionTabAccessibilityAndCycling() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let owner = AppController()
        let panel = WebPanelController(owner: owner, url: fixture.url("/root"))
        defer { panel.close() }

        let root = try require(panel.selectedIntegrationWebView, "missing root web view")
        try await waitForPath("/root", in: root)

        _ = try await root.evaluateJavaScript("window.open('about:blank', '_blank'); 'opened'")
        try await waitUntil("non-persistable popup tab") {
            panel.integrationTabStates.count == 2
                && panel.selectedIntegrationWebView?.url?.scheme == "about"
        }

        panel.openNewTab(url: fixture.url("/popup-source"))
        let source = try require(panel.selectedIntegrationWebView, "missing source tab")
        try await waitForPath("/popup-source", in: source)
        panel.openNewTab(url: fixture.url("/popup-child"))
        let child = try require(panel.selectedIntegrationWebView, "missing child tab")
        try await waitForPath("/popup-child", in: child)

        panel.selectIntegrationTab(webView: source)
        try expect(
            panel.workspaceTabURLs.map(\.path) == ["/root", "/popup-source", "/popup-child"],
            "workspace projection retained a non-web tab or changed tab order"
        )
        try expect(
            panel.selectedWorkspaceTabIndex == 1,
            "workspace selected index still used the unfiltered live-tab index"
        )

        let accessibilityStates = panel.integrationTabAccessibilityStates
        let selectedAccessibilityState = try require(
            accessibilityStates.first { $0.isSelected },
            "no real tab button exposed selected state"
        )
        try expect(
            !selectedAccessibilityState.title.isEmpty,
            "selected tab exposed an empty title"
        )
        try expect(
            selectedAccessibilityState.titleButtonLabel
                == "Select tab: \(selectedAccessibilityState.title)",
            "selected tab button accessibility label did not include its title"
        )
        try expect(
            selectedAccessibilityState.closeButtonLabel
                == "Close tab: \(selectedAccessibilityState.title)",
            "tab close button accessibility label did not include its title"
        )
        try expect(
            accessibilityStates.filter(\.isSelected).count == 1,
            "more than one tab button exposed selected state"
        )

        panel.cycleIntegrationTab(backward: false)
        try expect(
            panel.selectedIntegrationWebView === child,
            "forward tab cycling did not select the next live tab"
        )
        panel.cycleIntegrationTab(backward: true)
        try expect(
            panel.selectedIntegrationWebView === source,
            "backward tab cycling did not restore the previous live tab"
        )
        print("  PASS filtered workspace selection, accessible tabs and tab cycling")
    }

    private static func testProductionTabLimitBlocksWebsitePopups() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let owner = AppController()
        let rootURL = fixture.url("/root")
        let panel = WebPanelController(owner: owner, url: rootURL)
        defer { panel.close() }

        let root = try require(panel.selectedIntegrationWebView, "missing root web view")
        try await waitForPath("/root", in: root)
        let requestedURLs = (0..<(WebPanelController.maximumLiveTabs + 8)).map { index in
            URL(string: "\(rootURL.absoluteString)?tab=\(index)")!
        }
        panel.restoreWorkspaceTabs(requestedURLs, selectedIndex: 0)
        try expect(
            panel.integrationTabStates.count == WebPanelController.maximumLiveTabs,
            "workspace restore exceeded the live-tab limit"
        )

        let selected = try require(panel.selectedIntegrationWebView, "missing selected capped tab")
        _ = try await selected.evaluateJavaScript("window.open('about:blank', '_blank'); 'opened'")
        try await waitUntil("coalesced live-tab limit notice") {
            panel.integrationTabLimitNoticeCount == 1
        }
        try expect(
            panel.integrationTabStates.count == WebPanelController.maximumLiveTabs,
            "website popup bypassed the live-tab limit"
        )

        panel.openNewTab(url: fixture.url("/popup-child"))
        try expect(
            panel.integrationTabStates.count == WebPanelController.maximumLiveTabs,
            "explicit new tab bypassed the live-tab limit"
        )
        try expect(
            panel.integrationTabLimitNoticeCount == 1,
            "repeated tab-limit attempts were not coalesced into one notice"
        )

        panel.closeCurrentTab()
        panel.openNewTab(url: fixture.url("/popup-child"))
        try expect(
            panel.integrationTabStates.count == WebPanelController.maximumLiveTabs,
            "closing a tab did not release capacity for an explicit new tab"
        )
        print("  PASS live-tab cap blocks popup bursts and coalesces feedback")
    }

    private static func testProductionWebProcessTerminationHandlerHasRecoverableState() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let owner = AppController()
        let panel = WebPanelController(owner: owner, url: fixture.url("/root"))
        defer { panel.close() }
        let webView = try require(panel.selectedIntegrationWebView, "missing production web view")
        try await waitForPath("/root", in: webView)

        // There is no supported public API that deterministically kills a
        // WKWebView content process. Exercise the production delegate entry
        // point on its real WKWebView instead of relying on private selectors.
        panel.webViewWebContentProcessDidTerminate(webView)
        let terminationState = try require(state(for: webView, in: panel), "missing termination state")
        try expect(webView.navigationDelegate === panel, "termination delegate is not wired")
        try expect(terminationState.isShowingError, "termination did not show recovery UI")
        try expect(terminationState.failedURL?.path == "/root", "termination lost the current URL")
        try expect(
            BrowserSupport.isSafeToRetry(terminationState.failedRequest),
            "terminated GET page should be recoverable"
        )
        print("  PASS production process-termination recovery handler")
    }

    private static func testRealWKWebViewInvokesJavaScriptAndUploadUIDelegates() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let delegate = RecordingUIDelegate()
        let webView = makeIsolatedWebView()
        webView.uiDelegate = delegate

        webView.load(URLRequest(url: fixture.url("/dialogs")))
        try await waitForPath("/dialogs", in: webView)
        let result = try await javaScriptString("runDialogs()", in: webView)
        try expect(result == "true:delegate answer", "JavaScript dialog completion values were wrong")
        try expect(delegate.alertMessages == ["integration alert"], "alert delegate was not invoked")
        try expect(delegate.confirmMessages == ["integration confirm"], "confirm delegate was not invoked")
        try expect(delegate.promptMessages.first?.0 == "integration prompt", "prompt delegate was not invoked")
        try expect(delegate.promptMessages.first?.1 == "default", "prompt default value was lost")

        webView.load(URLRequest(url: fixture.url("/upload")))
        try await waitForPath("/upload", in: webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('upload').click(); 'clicked'")
        try await waitUntil("WKOpenPanelParameters callback") { delegate.uploadRequestCount == 1 }
        try expect(delegate.uploadAllowsMultipleSelection, "upload parameters lost the multiple flag")
        print("  PASS real WKWebView JavaScript dialogs and upload callback")
    }

    private static func testRealWKDownloadDelegateWritesOfflineAttachment() async throws {
        let fixture = try LocalHTTPFixture()
        defer { fixture.stop() }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("CornerFloat-WebKit-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: destination) }
        let delegate = RecordingDownloadDelegate(destination: destination)
        let webView = makeIsolatedWebView()
        webView.navigationDelegate = delegate

        webView.load(URLRequest(url: fixture.url("/download")))
        try await waitUntil("WKDownload finished") { delegate.isFinished }
        try expect(delegate.failure == nil, "WKDownload failed: \(delegate.failure?.localizedDescription ?? "unknown")")
        try expect(delegate.didBecomeDownload, "navigation response did not become WKDownload")
        try expect(delegate.suggestedFilename == "integration-download.txt", "download filename was lost")
        let downloaded = try Data(contentsOf: destination)
        try expect(downloaded == Data("CornerFloat offline download".utf8), "downloaded bytes were wrong")
        print("  PASS real WKDownload delegate and destination write")
    }

    private static func makeIsolatedWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 360), configuration: configuration)
    }

    private static func state(
        for webView: WKWebView,
        in panel: WebPanelController
    ) -> WebPanelController.IntegrationTabState? {
        panel.integrationTabStates.first { $0.webView === webView }
    }

    private static func waitForFailure(
        method: String,
        path: String,
        webView: WKWebView,
        panel: WebPanelController,
        fixture: LocalHTTPFixture
    ) async throws {
        try await waitUntil("\(method) \(path) failure state") {
            guard fixture.requestCount(method: method, path: path) >= 1,
                  let state = state(for: webView, in: panel) else { return false }
            return state.failedRequest?.httpMethod == method
                && state.failedURL?.path == path
                && state.isShowingError
        }
    }

    private static func waitForPath(_ path: String, in webView: WKWebView) async throws {
        try await waitUntil("WebKit load \(path)") {
            guard webView.url?.path == path else { return false }
            let ready = try? awaitJavaScriptBool(
                "location.pathname === '\(path)' && document.readyState === 'complete'",
                in: webView
            )
            return ready == true
        }
    }

    /// Polling evaluates synchronously through a short nested run-loop turn;
    /// this avoids registering a second navigation delegate on production views.
    private static func awaitJavaScriptBool(_ script: String, in webView: WKWebView) throws -> Bool {
        var result: Result<Bool, Error>?
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(value as? Bool ?? false)
            }
        }
        let deadline = Date(timeIntervalSinceNow: 0.25)
        while result == nil, RunLoop.current.run(mode: .default, before: deadline), Date() < deadline {}
        return try result?.get() ?? false
    }

    private static func javaScriptString(_ script: String, in webView: WKWebView) async throws -> String {
        let value = try await webView.evaluateJavaScript(script)
        return value as? String ?? ""
    }

    private static func javaScriptBool(_ script: String, in webView: WKWebView) async throws -> Bool {
        let value = try await webView.evaluateJavaScript(script)
        return value as? Bool ?? false
    }

    private static func waitUntil(
        _ description: String,
        timeout: TimeInterval = 8,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw IntegrationTestError.failed("timed out waiting for \(description)")
    }

    private static func removeIntegrationCookiesSynchronously(
        from store: WKWebsiteDataStore,
        matchingValue: String
    ) {
        var matchingCookies: [HTTPCookie]?
        store.httpCookieStore.getAllCookies { cookies in
            matchingCookies = cookies.filter {
                isLoopbackIntegrationCookie($0) && $0.value == matchingValue
            }
        }
        runMainLoop(until: { matchingCookies != nil })
        for cookie in matchingCookies ?? [] {
            var didDelete = false
            store.httpCookieStore.delete(cookie) { didDelete = true }
            runMainLoop(until: { didDelete })
        }
    }

    private static func integrationCookieValuesSynchronously(
        from store: WKWebsiteDataStore
    ) -> [String] {
        var values: [String]?
        store.httpCookieStore.getAllCookies { cookies in
            values = cookies
                .filter(isLoopbackIntegrationCookie)
                .map(\.value)
        }
        runMainLoop(until: { values != nil })
        return values ?? []
    }

    private static func isLoopbackIntegrationCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return cookie.name == "CornerFloatIntegration"
            && (domain == "127.0.0.1" || domain == "localhost")
    }

    private static func runMainLoop(
        timeout: TimeInterval = 1,
        until condition: () -> Bool
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) throws {
        guard condition() else { throw IntegrationTestError.failed(message()) }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw IntegrationTestError.failed(message) }
        return value
    }
}
