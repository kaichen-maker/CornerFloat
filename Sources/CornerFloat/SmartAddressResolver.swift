import Foundation

struct AddressShortcut: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var aliases: [String]
    var url: String
    let createdAt: Date
    var updatedAt: Date
}

enum SmartAddressResolver {
    private static let blockedSchemes: Set<String> = [
        "about", "blob", "data", "file", "ftp", "javascript", "mailto", "view-source"
    ]

    private static let shortcuts: [String: String] = [
        "google": "https://www.google.com/",
        "googlesearch": "https://www.google.com/",
        "chatgpt": "https://chatgpt.com/auth/login",
        "openaichat": "https://chatgpt.com/auth/login",
        "gmail": "https://mail.google.com/",
        "googlemail": "https://mail.google.com/"
    ]

    static func resolve(
        _ input: String,
        customShortcuts: [AddressShortcut] = []
    ) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = normalizedShortcutKey(trimmed)
        if let customShortcut = customShortcuts.first(where: { shortcut in
            shortcut.aliases.contains { normalizedShortcutKey($0) == key }
        }), let url = explicitWebURL(from: customShortcut.url) {
            return url
        }

        if let shortcut = shortcuts[key] {
            return URL(string: shortcut)
        }

        if startsWithWebScheme(trimmed) {
            return explicitWebURL(from: trimmed)
        }

        if let localURL = localURL(from: trimmed) {
            return localURL
        }

        guard !hasUnsupportedScheme(trimmed) else { return nil }

        if let domainURL = domainURL(from: trimmed) {
            return domainURL
        }

        return googleSearchURL(for: trimmed)
    }

    static func normalizedShortcutKey(_ input: String) -> String {
        input
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func startsWithWebScheme(_ input: String) -> Bool {
        let lowercased = input.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    private static func explicitWebURL(from input: String) -> URL? {
        guard !input.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              let components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        return components.url
    }

    private static func localURL(from input: String) -> URL? {
        guard isSingleAddressToken(input),
              let candidate = URLComponents(string: "http://\(input)"),
              let host = candidate.host?.lowercased(),
              isLocalHost(host),
              candidate.user == nil,
              candidate.password == nil else {
            return nil
        }
        return candidate.url
    }

    private static func domainURL(from input: String) -> URL? {
        guard isSingleAddressToken(input),
              let candidate = URLComponents(string: "https://\(input)"),
              let host = candidate.host?.lowercased(),
              isDomainHost(host),
              candidate.user == nil,
              candidate.password == nil else {
            return nil
        }
        return candidate.url
    }

    private static func isSingleAddressToken(_ input: String) -> Bool {
        !input.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
            && !input.contains("@")
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".test")
            || isIPv4Address(host)
            || host.contains(":")
    }

    private static func isDomainHost(_ host: String) -> Bool {
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              let topLevelLabel = labels.last,
              topLevelLabel.count >= 2,
              topLevelLabel.contains(where: \.isLetter) else {
            return false
        }

        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-"
            }
        }
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        return components.allSatisfy { component in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let value = Int(component) else {
                return false
            }
            return (0 ... 255).contains(value)
        }
    }

    private static func hasUnsupportedScheme(_ input: String) -> Bool {
        guard let colon = input.firstIndex(of: ":"), colon != input.startIndex else { return false }
        let scheme = input[..<colon]
        guard let first = scheme.first, first.isLetter else { return false }
        let isValidScheme = scheme.dropFirst().allSatisfy { character in
            character.isLetter
                || character.isNumber
                || character == "+"
                || character == "-"
                || character == "."
        }
        guard isValidScheme else { return false }

        let lowercasedScheme = scheme.lowercased()
        let remainder = input[input.index(after: colon)...]
        return blockedSchemes.contains(lowercasedScheme) || remainder.hasPrefix("//")
    }

    private static func googleSearchURL(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.percentEncodedQuery = "q=\(encodedQuery)"
        return components.url
    }
}
